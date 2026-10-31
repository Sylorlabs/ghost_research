#!/usr/bin/env python3
"""Recompute readiness after complete A4 replay integration."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_pareto_remediation_v10 import verify as verify_remediation


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
PRIOR = RESULTS / "readiness_iteration_4_7.json"
OUTPUT = RESULTS / "readiness_iteration_4_8.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def main() -> None:
    freeze = verify_remediation()
    if not (
        freeze["A4_production_integrated_calibration_arm"] is True
        and freeze["production_integrated_arms"] == 5
        and freeze["P3_complete"] is False
        and freeze["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("readiness 4.8 evidence invalid")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_4_8",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": sha(PRIOR),
        "remediation_freeze_sha256": sha(
            RESULTS / "pareto_remediation_v10_freeze.json"
        ),
        "progress": {
            "P2_complete": True,
            "A1_compatibility_audited_not_integrated": True,
            "A3_A9_production_integrated_calibration_arms": True,
            "A4_runtime_mount_ready": True,
            "A4_immutable_tools": 3,
            "A4_successful_tool_replays": 29,
            "A4_whole_graph_executions": 69,
            "A4_maximum_error": 0.0,
            "A4_base_contract_pairs_accepted": 23,
            "A4_shared_resource_receipts_charged": 1,
            "A4_hostile_batches_rejected_twice": 11,
            "A4_production_integrated_calibration_arm": True,
            "production_integrated_arms": 5,
            "required_arms": 10,
            "P3_complete": False,
            "heldout_source_runtime_graph_or_outcome_accessed": False,
        },
        "prerequisites": {
            "P1_external_control_conformance": False,
            "P2_independent_corpus_and_invocation_trace": True,
            "P3_complete_resource_meter": False,
            "P4_independent_typed_tool_verifier": True,
            "P5_native_compiler_deduplication": True,
            "P6_unchanged_prospective_freeze": True,
        },
        "authorization": {
            "prerequisites_passed": 4,
            "prerequisites_required": 6,
            "required_arms_production_integrated": 5,
            "required_arms": 10,
            "active_stop_conditions": 1,
            "prospective_trial_authorized": False,
        },
        "remaining_blockers": [
            "P1 still lacks the fourth complete source-faithful control",
            "A1 remains incompatible with the complete framework IR and is not integrated",
            "A5 and A7 are not integrated through the common runtime, contract, and shared receipt boundary",
            "A6 and A8 remain required fail-closed arms with incomplete declared controls",
            "all ten required arm paths do not yet have explicit metered outcomes",
            "zero candidate runtime inventions survive native deduplication and the final measured-search distinction remains unregistered"
        ],
        "remediation": {
            "next_action": (
                "audit and adapt A5 typed Stitch-style MDL without replacing "
                "its source-faithful algorithm with the existing replay "
                "matcher; then perform the same compatibility-first process "
                "for A7 rule inference"
            ),
            "required": True,
            "forbidden_shortcuts": [
                "do not relabel A4 replay tools as runtime inventions",
                "do not use A4 to substitute for A5 or A7 defining behavior",
                "do not count incomplete or incompatible arms as integrated",
                "do not mount or execute validation-v6 before authorization"
            ]
        },
        "interpretation": (
            "A4 is now a complete production-integrated calibration arm: "
            "its immutable historical library replays through the full "
            "framework surface, all numerical and retained-state checks pass, "
            "and 23 strict contract pairs share one metered receipt without "
            "double counting. Integrated truth advances to five of ten, but "
            "P1 and P3 remain open and prospective execution stays forbidden."
        )
    }
    OUTPUT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_READINESS_ITERATION_4_8"
        " verdict=FOUNDRY_V6_NOT_READY"
        " prerequisites=4/6 integrated=5/10"
        " A4=PASS prospective=false"
    )


if __name__ == "__main__":
    main()
