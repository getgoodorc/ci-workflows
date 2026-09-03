#!/usr/bin/env python3
"""Enforce that harness.yaml only ever tightens.

The north star's rule: *ratchets only tighten*, and any change that weakens a
gate is itself a loud, reviewable event. Until something checks that, every
harness.yaml is a declaration with no enforcer — a comment that happens to be
valid YAML.

This compares the working tree's harness.yaml against the copy on the merge
base and fails if:

  * `level` moved down the pyramid,
  * `target` moved down (retreating from an agreed target is a decision, not a
    diff — it should be argued for, not slipped in),
  * a gate that was `enabled: true` is now false or missing.

Adding gaps, adding gates, or raising a level all pass. That asymmetry is the
whole point.

Exit 0 = tightened or unchanged. Exit 1 = loosened. Exit 2 = usage/parse error.

Canonical copy: getgoodorc/ci-workflows/tools/ratchet.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    print("ratchet: PyYAML is required (pip install pyyaml)", file=sys.stderr)
    sys.exit(2)

# Ordered weakest to strongest. A repo may sit "below the rail" before the
# harness exists at all, which is a legitimate starting state, not a failure.
LEVELS = ["none", "rail", "l1", "l2", "l3", "l4", "l5", "l6"]


def rank(level: str) -> int:
    key = str(level).strip().lower()
    if key not in LEVELS:
        raise ValueError(f"unknown level {level!r}; expected one of {', '.join(LEVELS)}")
    return LEVELS.index(key)


def enabled_gates(doc: dict) -> set[str]:
    return {
        str(g.get("id"))
        for g in (doc.get("gates") or [])
        if isinstance(g, dict) and g.get("enabled") is True and g.get("id")
    }


def load(text: str) -> dict:
    doc = yaml.safe_load(text)
    if not isinstance(doc, dict):
        raise ValueError("harness.yaml must be a mapping")
    return doc


def baseline(path: str, ref: str) -> dict | None:
    """The committed harness.yaml at `ref`, or None if it did not exist yet."""
    try:
        out = subprocess.run(
            ["git", "show", f"{ref}:{path}"],
            capture_output=True, text=True, check=True,
        ).stdout
    except subprocess.CalledProcessError:
        return None
    return load(out)


def main(argv: list[str]) -> int:
    path = argv[1] if len(argv) > 1 else "harness.yaml"
    ref = argv[2] if len(argv) > 2 else "origin/main"

    current_file = Path(path)
    if not current_file.exists():
        print(f"ratchet: {path} not found", file=sys.stderr)
        return 2

    current = load(current_file.read_text())
    previous = baseline(path, ref)

    if previous is None:
        print(f"ratchet: no {path} at {ref} — nothing to compare, this is the first one")
        return 0

    failures: list[str] = []

    for field in ("level", "target"):
        was, now = previous.get(field, "none"), current.get(field, "none")
        if rank(now) < rank(was):
            failures.append(
                f"{field} moved DOWN: {was} -> {now}. "
                f"Retreating is a decision to argue for, not a diff to slip in."
            )

    lost = enabled_gates(previous) - enabled_gates(current)
    for gate in sorted(lost):
        failures.append(f"gate '{gate}' was enabled at {ref} and is not enabled now.")

    if failures:
        print(f"ratchet: {path} LOOSENED relative to {ref}\n", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        print(
            "\nIf this is deliberate, say so in the PR description — weakening a "
            "gate should be a conversation, which is exactly what this failure "
            "forces.",
            file=sys.stderr,
        )
        return 1

    gained = enabled_gates(current) - enabled_gates(previous)
    if gained:
        print(f"ratchet: tightened — new gates: {', '.join(sorted(gained))}")
    else:
        print("ratchet: unchanged")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
