#!/usr/bin/env python3
"""Recompute readiness after the frozen A1 compatibility negative."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_pareto_remediation_v9 import verify as verify_remediation


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
PRIOR = RESULTS / "readiness_iteration_4_6.json"
OUTPUT = RESULTS / "readiness_iteration_4_7.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def run() -> None:
    freeze = verify_remediation()
    audit = json.loads(
        (
            RESULTS / "phase93_a1_ir_compatibility_audit.json"
        ).read_text()
    )
    resource = json.loads(
        (
            RESULTS / "phase94_a1_ir_compatibility_resource_audit.json"
        ).read_text()
    )
    if not (
        audit["status"]
        == "A1_DIRECT_ADAPTER_REJECTED_INCOMPLETE_IR_SURFACE"
        and resource["status"] == "A1_IR_COMPATIBILITY_RESOURCE_PASS"
        and freeze["A1_production_integrated"] is False
        and freeze["production_integrated_arms"] == 4
        and freeze["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("readiness 4.7 evidence invalid")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_4_7",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": sha(PRIOR),
        "remediation_freeze_sha256": sha(
            RESULTS / "pareto_remediation_v9_freeze.json"
        ),
        "progress": {
            "P2_complete": True,
            "A3_A9_production_integrated_calibration_arms": True,
            "A1_compatibility_audited": True,
            "A1_runtime_ops": 22,
            "A1_direct_exact_ATen_targets": 9,
            "A1_direct_exact_calls": 143,
            "A1_whole_graphs_direct": 4,
            "A1_exact_constructor_pattern_candidates": 0,
            "A1_production_integrated": False,
            "production_integrated_arms": 4,
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
            "required_arms_production_integrated": 4,
            "required_arms": 10,
            "active_stop_conditions": 1,
            "prospective_trial_authorized": False,
        },
        "remaining_blockers": [
            "P1 still lacks the fourth complete source-faithful control",
            "A1 requires a faithful ATen-to-Operator-v5 typed IR lowering bridge and a non-reference calibration construction",
            "A4, A5, and A7 are not integrated through the frozen contract and shared receipt overlay",
            "A6 and A8 remain required fail-closed arms with incomplete declared controls",
            "all ten required arm paths do not yet have explicit metered outcomes",
            "zero candidate runtime inventions survive native deduplication and the final measured-search distinction remains unregistered"
        ],
        "remediation": {
            "next_action": (
                "implement and independently falsify-test an evaluator-owned "
                "ATen-to-Operator-v5 typed lowering bridge; do not promote A1 "
                "until all 23 calibration graphs have explicit exact or "
                "fail-closed outcomes and at least one frozen non-reference "
                "constructor path executes"
            ),
            "required": True,
            "forbidden_shortcuts": [
                "do not call 9/41 target coverage a complete A1 adapter",
                "do not treat reference execution alone as conditional construction",
                "do not extend the frozen A1 IR or grammar while claiming v5.1 behavior",
                "do not mount or execute validation-v6 before authorization"
            ]
        },
        "interpretation": (
            "A1 is a real historical constructor, but its frozen typed IR is "
            "not the calibration framework IR. The complete compatibility "
            "audit rejects a direct wrapper: only four graphs are wholly "
            "directly lowerable and none exercises a non-reference A1 "
            "constructor. Integration correctly remains four of ten while "
            "the evaluator-owned lowering bridge is built."
        )
    }
    OUTPUT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_READINESS_ITERATION_4_7"
        " verdict=FOUNDRY_V6_NOT_READY"
        " prerequisites=4/6"
        " integrated=4/10"
        " A1_direct=REJECTED"
        " prospective=false"
    )


if __name__ == "__main__":
    run()
