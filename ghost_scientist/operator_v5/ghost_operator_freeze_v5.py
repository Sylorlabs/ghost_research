#!/usr/bin/env python3
"""Create or verify the prospective Operator v5 SHA-256 freeze record."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib

from ghost_operator_core_v5 import canonical_json


BASE_FILES = (
    "PROTOCOL.md",
    "README.md",
    "ghost_operator_candidate_v5.py",
    "ghost_operator_controls_v5.py",
    "ghost_operator_core_v5.py",
    "ghost_operator_corpus_v5.py",
    "ghost_operator_development_v5.py",
    "ghost_operator_egraph_v5.py",
    "ghost_operator_evaluator_v5.py",
    "ghost_operator_freeze_v5.py",
    "ghost_operator_learn_v5.py",
    "ghost_operator_merge_outcomes_v5.py",
    "ghost_operator_synthesis_v5.py",
    "ghost_operator_trial_v5.py",
    "ghost_operator_validate_grammar_v5.py",
    "ghost_operator_verify_candidate_v5.py",
    "containment/ghost_operator_allowlist_v5.zig",
    "containment/ghost_operator_probe_v5.zig",
)
HELDOUT_NAMES = ("heldout", "heldout_corpus", "heldout_trial")


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _materialize_frozen_controls(root: pathlib.Path) -> None:
    grammar_source = root / "results/algebraic_grammar_v5.json"
    fixed_source = root / "results/fixed_signature_portfolio_v5.json"
    grammar = json.loads(grammar_source.read_text(encoding="utf-8"))
    grammar["status"] = "FROZEN_PRE_HELDOUT"
    grammar["frozen_from_sha256"] = digest(grammar_source)
    (root / "results/frozen_grammar_v5.json").write_text(
        canonical_json(grammar) + "\n", encoding="utf-8"
    )
    fixed = json.loads(fixed_source.read_text(encoding="utf-8"))
    fixed["status"] = "FROZEN_PRE_HELDOUT"
    fixed["frozen_from_sha256"] = digest(fixed_source)
    (root / "results/frozen_fixed_portfolio_v5.json").write_text(
        canonical_json(fixed) + "\n", encoding="utf-8"
    )


def freeze_paths(root: pathlib.Path) -> list[pathlib.Path]:
    paths = [root / relative for relative in BASE_FILES]
    paths.extend(
        path
        for path in (root / "results").rglob("*")
        if path.is_file() and path.name != "protocol_freeze_v5.txt"
    )
    unique = sorted(set(path.resolve() for path in paths))
    missing = [path for path in unique if not path.is_file()]
    if missing:
        raise RuntimeError(f"freeze input missing: {missing[0]}")
    return unique


def create(root: pathlib.Path, output: pathlib.Path) -> None:
    for name in HELDOUT_NAMES:
        if (root / "results" / name).exists():
            raise RuntimeError(f"{name} exists before protocol freeze")
    _materialize_frozen_controls(root)
    paths = freeze_paths(root)
    records = [
        (digest(path), path.relative_to(root).as_posix()) for path in paths
    ]
    lines = [
        "GHOST_OPERATOR_PROTOCOL_FREEZE_V5",
        "state=PRE_HELDOUT",
        "heldout_count=24",
        "heldout_family_count=8",
        "heldout_seed_hex=0x67686f73745f6f70657261746f725f76355f68656c646f75745f3031",
        "heldout_repetitions=11",
        "joint_score=four_objective_equal_weight_geometric_mean",
        "absolute_tolerance=1e-5",
        "fixed_portfolio_improvement_gate=0.01",
        "oracle_regret_gate=0.03",
        "max_stock_losses=2",
        "max_stock_loss_ratio=1.10",
        f"record_count={len(records)}",
        "sha256_records_begin",
        *(f"{sha}  {relative}" for sha, relative in records),
        "sha256_records_end",
    ]
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(
        "GHOST_OPERATOR_FREEZE_V5 PASS"
        f" records={len(records)} freeze_sha256={digest(output)}"
    )


def verify(root: pathlib.Path, freeze: pathlib.Path) -> None:
    lines = freeze.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "GHOST_OPERATOR_PROTOCOL_FREEZE_V5":
        raise RuntimeError("freeze record contract mismatch")
    try:
        begin = lines.index("sha256_records_begin")
        end = lines.index("sha256_records_end")
    except ValueError as exc:
        raise RuntimeError("freeze record markers missing") from exc
    if begin >= end:
        raise RuntimeError("freeze record order is invalid")
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
        "GHOST_OPERATOR_FREEZE_VERIFY_V5 PASS"
        f" records={checked} freeze_sha256={digest(freeze)}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("create", "verify"))
    parser.add_argument(
        "--root", default=str(pathlib.Path(__file__).resolve().parent)
    )
    parser.add_argument("--freeze")
    args = parser.parse_args()
    root = pathlib.Path(args.root).resolve()
    freeze = (
        pathlib.Path(args.freeze).resolve()
        if args.freeze
        else root / "results/protocol_freeze_v5.txt"
    )
    if args.command == "create":
        create(root, freeze)
    else:
        verify(root, freeze)


if __name__ == "__main__":
    main()

