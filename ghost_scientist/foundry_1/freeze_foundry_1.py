#!/usr/bin/env python3
"""Create and verify the Foundry-1 post-calibration transfer freeze."""

from __future__ import annotations

import argparse
import hashlib
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
FREEZE = RESULTS / "protocol_freeze.txt"
BASE = (
    "README.md",
    "PROTOCOL.md",
    "candidate_forge.py",
    "independent_evaluator.py",
    "run_calibration.py",
    "resource_meter.py",
    "run_remediation.py",
    "recompute_readiness.py",
    "results/corpus_manifest.json",
    "results/phase1.json",
    "results/learned_tools.json",
)


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def create() -> None:
    if (RESULTS / "phase2.json").exists() or (RESULTS / "phase3_remediation.json").exists():
        raise RuntimeError("post-freeze result exists before freeze creation")
    paths = [HERE / relative for relative in BASE]
    missing = [path for path in paths if not path.is_file()]
    if missing:
        raise RuntimeError(f"freeze input missing: {missing[0].relative_to(HERE)}")
    records = [(digest(path), path.relative_to(HERE).as_posix()) for path in paths]
    lines = [
        "FOUNDRY_1_PROTOCOL_FREEZE_V1",
        "state=POST_PHASE1_PRE_PHASE2",
        "phase2_kind_count=4",
        "candidate_mutation_after_freeze=forbidden",
        "phase2_outcome_driven_change=forbidden",
        f"record_count={len(records)}",
        "sha256_records_begin",
        *(f"{sha}  {relative}" for sha, relative in records),
        "sha256_records_end",
    ]
    RESULTS.mkdir(parents=True, exist_ok=True)
    FREEZE.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_1_FREEZE_CREATE_PASS"
        f" records={len(records)} freeze_sha256={digest(FREEZE)}"
    )


def verify() -> None:
    lines = FREEZE.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "FOUNDRY_1_PROTOCOL_FREEZE_V1":
        raise RuntimeError("freeze contract mismatch")
    try:
        begin = lines.index("sha256_records_begin")
        end = lines.index("sha256_records_end")
    except ValueError as exc:
        raise RuntimeError("freeze markers missing") from exc
    checked = 0
    for line in lines[begin + 1 : end]:
        expected, relative = line.split("  ", 1)
        path = HERE / relative
        if not path.is_file() or digest(path) != expected:
            raise RuntimeError(f"freeze digest mismatch: {relative}")
        checked += 1
    if f"record_count={checked}" not in lines:
        raise RuntimeError("freeze record count mismatch")
    print(
        "FOUNDRY_1_FREEZE_VERIFY_PASS"
        f" records={checked} freeze_sha256={digest(FREEZE)}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("create", "verify"))
    args = parser.parse_args()
    if args.command == "create":
        create()
    else:
        verify()


if __name__ == "__main__":
    main()

