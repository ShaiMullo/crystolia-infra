#!/usr/bin/env python3
"""Generate and validate the Crystolia platform manifest lock.

Authoring source : domains.manifest.yaml   (edit this)
Generated artifact: domains.lock.json       (consumed by Terraform / app / CI)
Schema           : domains.schema.json      (validates the resolved lock)

The lock is the YAML with `defaults` deep-merged into every market and removed,
so consumers read fully-resolved records without re-implementing the merge.

Usage:
  python3 generate.py            # write domains.lock.json + validate
  python3 generate.py --check    # CI: regenerate in memory, fail on drift + validate
"""
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

import yaml
from jsonschema import Draft7Validator

HERE = Path(__file__).resolve().parent
SRC = HERE / "domains.manifest.yaml"
LOCK = HERE / "domains.lock.json"
SCHEMA = HERE / "domains.schema.json"


def deep_merge(base: dict, override: dict) -> dict:
    """Recursively merge override onto base. Dicts merge; lists/scalars replace."""
    out = copy.deepcopy(base)
    for key, value in override.items():
        if key in out and isinstance(out[key], dict) and isinstance(value, dict):
            out[key] = deep_merge(out[key], value)
        else:
            out[key] = copy.deepcopy(value)
    return out


def resolve(manifest: dict) -> dict:
    """Merge `defaults` into each market; emit {version, markets[resolved]}."""
    defaults = manifest.get("defaults", {})
    markets = [deep_merge(defaults, m) for m in manifest.get("markets", [])]
    return {"version": manifest["version"], "markets": markets}


def serialize(lock: dict) -> str:
    """Deterministic JSON: sorted keys, 2-space indent, trailing newline."""
    return json.dumps(lock, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def validate(lock: dict) -> list[str]:
    schema = json.loads(SCHEMA.read_text())
    validator = Draft7Validator(schema)
    return [
        f"  - {'/'.join(map(str, e.path))}: {e.message}"
        for e in sorted(validator.iter_errors(lock), key=lambda e: list(e.path))
    ]


def main(argv: list[str]) -> int:
    check = "--check" in argv[1:]

    manifest = yaml.safe_load(SRC.read_text())
    lock = resolve(manifest)
    rendered = serialize(lock)

    errors = validate(lock)
    if errors:
        print(f"✗ schema validation failed ({len(errors)} error(s)):")
        print("\n".join(errors))
        return 1

    if check:
        current = LOCK.read_text() if LOCK.exists() else ""
        if current != rendered:
            print("✗ domains.lock.json is stale — run `python3 generate.py` and commit.")
            return 1
        print(f"✓ lock in sync and valid ({len(lock['markets'])} markets).")
        return 0

    LOCK.write_text(rendered)
    print(f"✓ wrote {LOCK.name} and validated ({len(lock['markets'])} markets).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
