#!/usr/bin/env python3
"""Merge independently measured Operator v5 outcome shards fail-closed."""

from __future__ import annotations

import argparse
import json
import pathlib

from ghost_operator_core_v5 import canonical_json, file_sha256


def merge(inputs: list[pathlib.Path], output: pathlib.Path) -> None:
    rows = {}
    for path in inputs:
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            row = json.loads(line)
            key = (row["opaque_id"], int(row["plan_index"]))
            if key in rows:
                raise ValueError(f"duplicate outcome {key} in {path}:{number}")
            rows[key] = row
    if not rows:
        raise ValueError("no outcome rows")
    output.write_text(
        "\n".join(canonical_json(rows[key]) for key in sorted(rows)) + "\n",
        encoding="utf-8",
    )
    print(
        "GHOST_OPERATOR_MERGE_OUTCOMES_V5 PASS"
        f" inputs={len(inputs)} outcomes={len(rows)}"
        f" output_sha256={file_sha256(output)}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("inputs", type=pathlib.Path, nargs="+")
    args = parser.parse_args()
    merge(args.inputs, args.output)


if __name__ == "__main__":
    main()

