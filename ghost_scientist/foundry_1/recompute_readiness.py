#!/usr/bin/env python3
"""Independent receipt-only Foundry-1 readiness recomputation."""

from __future__ import annotations

import json
import pathlib

from freeze_foundry_1 import digest, verify
from independent_evaluator import canonical_json, parse_tool


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def recompute() -> dict[str, object]:
    verify()
    phase1 = json.loads((RESULTS / "phase1.json").read_text(encoding="utf-8"))
    phase2 = json.loads((RESULTS / "phase2.json").read_text(encoding="utf-8"))
    remediation = json.loads(
        (RESULTS / "phase3_remediation.json").read_text(encoding="utf-8")
    )
    library = json.loads((RESULTS / "learned_tools.json").read_text(encoding="utf-8"))
    require(phase1["version"] == "FOUNDRY_PHASE1_V1", "phase1 schema mismatch")
    require(phase2["version"] == "FOUNDRY_PHASE2_V1", "phase2 schema mismatch")
    require(
        remediation["version"] == "FOUNDRY_REMEDIATION_V1",
        "remediation schema mismatch",
    )
    tools = library["tools"]
    require(set(tools) == {"declarations", "csv_width", "sleep_loop", "missing_arg"}, "tool coverage mismatch")
    for tool in tools.values():
        parse_tool(tool)
    p1 = phase1["pilot"]["summary"]
    p2 = phase2["phase2"]["summary"]
    gates = {
        "G01_four_machine_selected_tools": len(tools) == 4,
        "G02_phase1_exact": p1["candidate_exact"] == p1["tasks"] == 4,
        "G03_post_freeze_phase2_exact": p2["candidate_exact"] == p2["tasks"] == 4,
        "G04_direct_reuse_receipts": p2["direct_reuse_receipts"] == 4,
        "G05_causal_removal": p2["causal_removal_losses"] >= 3,
        "G06_fixed_portfolio_beaten": p2["candidate_beats_strong_fixed"] is True,
        "G07_independent_verifier_attacks": phase1["independent_verifier_hostile_rejections"] >= 4,
        "G08_freeze_unchanged": True,
        "G09_remediation_executed": remediation["status"] == "EXECUTED_VALID_NEGATIVE",
    }
    prerequisites = remediation["prerequisite_progress"]
    authorized = all(
        prerequisites[key]
        for key in (
            "P1_external_control_conformance",
            "P2_independent_corpus_and_invocation_trace",
            "P3_complete_resource_meter",
            "P4_independent_typed_tool_verifier",
            "P5_native_compiler_deduplication",
            "P6_unchanged_prospective_freeze",
        )
    )
    verdict = "FOUNDRY_V6_AUTHORIZED" if authorized else "FOUNDRY_V6_NOT_READY"
    return {
        "version": "FOUNDRY_READINESS_RECOMPUTE_V1",
        "verdict": verdict,
        "scientific_trial_executed": False,
        "gates": gates,
        "gates_passed": sum(gates.values()),
        "gates_total": len(gates),
        "prerequisites": prerequisites,
        "freeze_sha256": digest(RESULTS / "protocol_freeze.txt"),
        "phase1_sha256": digest(RESULTS / "phase1.json"),
        "phase2_sha256": digest(RESULTS / "phase2.json"),
        "remediation_sha256": digest(RESULTS / "phase3_remediation.json"),
        "interpretation": (
            "Autonomous bounded tool construction and post-freeze local transfer worked, "
            "but the strong fixed portfolio tied it and the external-control, external-corpus, "
            "complete-meter, and compiler-dedup prerequisites remain absent."
        ),
    }


def main() -> None:
    payload = recompute()
    (RESULTS / "readiness.json").write_text(canonical_json(payload) + "\n", encoding="utf-8")
    print(
        f"{payload['verdict']} gates={payload['gates_passed']}/{payload['gates_total']}"
        f" freeze_sha256={payload['freeze_sha256']}"
    )


if __name__ == "__main__":
    main()

