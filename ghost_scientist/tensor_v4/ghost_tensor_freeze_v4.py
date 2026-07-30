#!/usr/bin/env python3
"""Create or verify the prospective Tensor v4 SHA-256 freeze record."""

from __future__ import annotations

import argparse
import hashlib
import pathlib
from collections.abc import Iterable


BASE_FILES = (
    "PROTOCOL.md",
    "README.md",
    "ghost_tensor_candidate_v4.py",
    "ghost_tensor_constructor_v4.py",
    "ghost_tensor_core_v4.py",
    "ghost_tensor_egraph_v4.py",
    "ghost_tensor_evaluator_v4.py",
    "ghost_tensor_extract_v4.py",
    "ghost_tensor_freeze_v4.py",
    "ghost_tensor_trial_v4.py",
    "ghost_tensor_verify_v4.py",
    "containment/ghost_tensor_allowlist_v4.zig",
    "containment/ghost_tensor_probe_v4.zig",
)
EVIDENCE_GLOBS = (
    "results/development/manifest.tsv",
    "results/development/private_audit.jsonl",
    "results/development/outcomes.jsonl",
    "results/development/grammar.json",
    "results/development/selection_ledger.tsv",
    "results/development/public/*.json",
    "results/validation/manifest.tsv",
    "results/validation/private_audit.jsonl",
    "results/validation/public/*.json",
    "results/validation/trial/ledger.jsonl",
    "results/validation/trial/summary.json",
    "results/validation/trial_negative_absolute_tolerance/ledger.jsonl",
    "results/validation/trial_negative_absolute_tolerance/summary.json",
)


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def freeze_paths(root: pathlib.Path) -> list[pathlib.Path]:
    paths = [root / relative for relative in BASE_FILES]
    for pattern in EVIDENCE_GLOBS:
        paths.extend(root.glob(pattern))
    unique = sorted(set(path.resolve() for path in paths))
    missing = [path for path in unique if not path.is_file()]
    if missing:
        raise RuntimeError(f"freeze input missing: {missing[0]}")
    if (root / "results/heldout").exists():
        raise RuntimeError("heldout directory exists before protocol freeze")
    return unique


def relative_records(
    root: pathlib.Path, paths: Iterable[pathlib.Path]
) -> list[tuple[str, str]]:
    return [
        (digest(path), path.relative_to(root).as_posix())
        for path in paths
    ]


def create(root: pathlib.Path, output: pathlib.Path) -> None:
    records = relative_records(root, freeze_paths(root))
    lines = [
        "GHOST_TENSOR_PROTOCOL_FREEZE_V4",
        "state=PRE_HELDOUT",
        "heldout_count=24",
        "heldout_families=bart,llama",
        "heldout_seed_hex=0x74656e736f725f76345f68656c645f3031",
        "heldout_repetitions=11",
        f"record_count={len(records)}",
        "sha256_records_begin",
        *(f"{sha}  {relative}" for sha, relative in records),
        "sha256_records_end",
    ]
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(
        "GHOST_TENSOR_FREEZE_V4 PASS"
        f" records={len(records)} freeze_sha256={digest(output)}"
    )


def verify(root: pathlib.Path, freeze: pathlib.Path) -> None:
    lines = freeze.read_text(encoding="utf-8").splitlines()
    try:
        begin = lines.index("sha256_records_begin")
        end = lines.index("sha256_records_end")
    except ValueError as exc:
        raise RuntimeError("freeze record markers missing") from exc
    if begin >= end or lines[0] != "GHOST_TENSOR_PROTOCOL_FREEZE_V4":
        raise RuntimeError("freeze record contract mismatch")
    checked = 0
    for line in lines[begin + 1 : end]:
        try:
            expected, relative = line.split("  ", 1)
        except ValueError as exc:
            raise RuntimeError("malformed freeze digest record") from exc
        path = root / relative
        if not path.is_file() or digest(path) != expected:
            raise RuntimeError(f"freeze digest mismatch: {relative}")
        checked += 1
    if f"record_count={checked}" not in lines:
        raise RuntimeError("freeze record count mismatch")
    print(
        "GHOST_TENSOR_FREEZE_VERIFY_V4 PASS"
        f" records={checked} freeze_sha256={digest(freeze)}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("create", "verify"))
    parser.add_argument("--root", default=str(pathlib.Path(__file__).resolve().parent))
    parser.add_argument("--freeze")
    args = parser.parse_args()
    root = pathlib.Path(args.root).resolve()
    freeze = (
        pathlib.Path(args.freeze).resolve()
        if args.freeze
        else root / "results/protocol_freeze_v4.txt"
    )
    if args.command == "create":
        create(root, freeze)
    else:
        verify(root, freeze)


if __name__ == "__main__":
    main()
