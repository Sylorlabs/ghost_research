#!/usr/bin/env python3
"""Create or verify the chained Operator v5.1 prospective freeze."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys


HERE = pathlib.Path(__file__).resolve().parent
V5 = HERE.parent / "operator_v5"
sys.path.insert(0, str(V5))

from ghost_operator_core_v5 import canonical_json  # noqa: E402
from ghost_operator_freeze_v5 import verify as verify_v5  # noqa: E402


LOCAL_FILES = (
    "PROTOCOL.md",
    "README.md",
    "ghost_operator_freeze_v5_1.py",
    "ghost_operator_refit_v5_1.py",
    "ghost_operator_trial_v5_1.py",
    "results/refit_summary_v5_1.json",
    "results/retrospective_v5_heldout_v5_1.json",
    "results/candidate_replay_v5_1.jsonl",
)
V5_POSTFREEZE_EVIDENCE = (
    "ghost_operator_heldout_generate_v5.py",
    "results/heldout_corpus/generation_receipt.json",
    "results/heldout_corpus/manifest.tsv",
    "results/heldout_corpus/provenance.private.jsonl",
    "results/heldout_trial/candidate_receipts.jsonl",
    "results/heldout_trial/containment.json",
    "results/heldout_trial/control_summary.json",
    "results/heldout_trial/outcomes.jsonl",
    "results/heldout_trial/verdict.json",
)


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def materialize(root: pathlib.Path) -> None:
    grammar_source = root / "results/calibrated_grammar_v5_1.json"
    controls_source = root / "results/fixed_portfolio_v5_1.json"
    grammar = json.loads(grammar_source.read_text(encoding="utf-8"))
    grammar["status"] = "V5_1_FROZEN_PRE_HELDOUT"
    grammar["frozen_from_sha256"] = digest(grammar_source)
    (root / "results/frozen_grammar_v5_1.json").write_text(
        canonical_json(grammar) + "\n", encoding="utf-8"
    )
    controls = json.loads(controls_source.read_text(encoding="utf-8"))
    controls["status"] = "V5_1_FROZEN_PRE_HELDOUT"
    controls["frozen_from_sha256"] = digest(controls_source)
    (root / "results/frozen_fixed_portfolio_v5_1.json").write_text(
        canonical_json(controls) + "\n", encoding="utf-8"
    )


def paths(root: pathlib.Path) -> list[tuple[pathlib.Path, str]]:
    records = []
    for relative in LOCAL_FILES + (
        "results/calibrated_grammar_v5_1.json",
        "results/fixed_portfolio_v5_1.json",
        "results/frozen_grammar_v5_1.json",
        "results/frozen_fixed_portfolio_v5_1.json",
    ):
        records.append((root / relative, f"operator_v5_1/{relative}"))
    for relative in V5_POSTFREEZE_EVIDENCE:
        records.append((V5 / relative, f"operator_v5/{relative}"))
    records.append(
        (
            V5 / "results/protocol_freeze_v5.txt",
            "operator_v5/results/protocol_freeze_v5.txt",
        )
    )
    missing = [path for path, _relative in records if not path.is_file()]
    if missing:
        raise RuntimeError(f"v5.1 freeze input missing: {missing[0]}")
    return records


def create(root: pathlib.Path, output: pathlib.Path) -> None:
    if (root / "results/heldout_corpus").exists() or (
        root / "results/heldout_trial"
    ).exists():
        raise RuntimeError("v5.1 heldout exists before freeze")
    verify_v5(V5, V5 / "results/protocol_freeze_v5.txt")
    materialize(root)
    records = [(digest(path), relative) for path, relative in paths(root)]
    lines = [
        "GHOST_OPERATOR_PROTOCOL_FREEZE_V5_1",
        "state=PRE_HELDOUT",
        "predecessor_verdict=GHOST_OPERATOR_HELDOUT_V5_FAIL",
        "heldout_count=24",
        "heldout_seed_hex=0x67686f73745f6f70657261746f725f76355f315f68656c646f75745f3032",
        "heldout_repetitions=11",
        "fixed_portfolio_improvement_gate=0.01",
        "all_v5_gates_unchanged=true",
        f"record_count={len(records)}",
        "sha256_records_begin",
        *(f"{sha}  {relative}" for sha, relative in records),
        "sha256_records_end",
    ]
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(
        "GHOST_OPERATOR_FREEZE_V5_1 PASS"
        f" records={len(records)} freeze_sha256={digest(output)}"
    )


def verify(root: pathlib.Path, freeze: pathlib.Path) -> None:
    verify_v5(V5, V5 / "results/protocol_freeze_v5.txt")
    lines = freeze.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "GHOST_OPERATOR_PROTOCOL_FREEZE_V5_1":
        raise RuntimeError("v5.1 freeze contract mismatch")
    begin = lines.index("sha256_records_begin")
    end = lines.index("sha256_records_end")
    base = root.parent
    checked = 0
    for line in lines[begin + 1 : end]:
        expected, relative = line.split("  ", 1)
        path = base / relative
        if not path.is_file() or digest(path) != expected:
            raise RuntimeError(f"v5.1 freeze digest mismatch: {relative}")
        checked += 1
    if f"record_count={checked}" not in lines:
        raise RuntimeError("v5.1 freeze record count mismatch")
    print(
        "GHOST_OPERATOR_FREEZE_VERIFY_V5_1 PASS"
        f" records={checked} freeze_sha256={digest(freeze)}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("create", "verify"))
    args = parser.parse_args()
    freeze = HERE / "results/protocol_freeze_v5_1.txt"
    if args.command == "create":
        create(HERE, freeze)
    else:
        verify(HERE, freeze)


if __name__ == "__main__":
    main()
