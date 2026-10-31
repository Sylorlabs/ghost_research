#!/usr/bin/env python3
"""Recompute readiness after A3/A9 shared-receipt integration."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_pareto_remediation_v8 import verify as verify_remediation


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
PRIOR = RESULTS / "readiness_iteration_4_5.json"
OUTPUT = RESULTS / "readiness_iteration_4_6.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def run() -> None:
    freeze = verify_remediation()
    batch = json.loads(
        (
            RESULTS / "phase91_shared_resource_batch_conformance.json"
        ).read_text()
    )
    resources = json.loads(
        (
            RESULTS
            / "phase92_shared_resource_batch_resource_audit.json"
        ).read_text()
    )
    if not (
        batch["status"] == "SHARED_RESOURCE_BATCH_CONFORMANCE_PASS"
        and resources["status"] == "SHARED_RESOURCE_BATCH_RESOURCE_PASS"
        and freeze["production_integrated_arms"] == 4
        and freeze["P3_complete"] is False
        and freeze["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("readiness 4.6 evidence invalid")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_4_6",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": sha(PRIOR),
        "remediation_freeze_sha256": sha(
            RESULTS / "pareto_remediation_v8_freeze.json"
        ),
        "progress": {
            "P2_complete": True,
            "arm_adapter_contract_ready": True,
            "framework_runtime_mount_component_ready": True,
            "shared_resource_receipt_overlay_ready": True,
            "A3_A9_complete_contract_batches_ready": True,
            "A3_A9_production_integrated_calibration_arms": True,
            "base_contract_pairs_accepted": 46,
            "shared_resource_receipts_charged": 2,
            "hostile_batches_rejected_twice": 9,
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
            "A1, A4, A5, and A7 are not integrated through the frozen contract and shared receipt overlay",
            "A6 and A8 remain required fail-closed arms with unavailable declared dependencies",
            "all ten required arm paths do not yet have explicit metered outcomes",
            "zero candidate runtime inventions survive native deduplication and the final measured-search distinction remains unregistered"
        ],
        "remediation": {
            "next_action": (
                "adapt A1 next as the simplest historical fixed baseline, "
                "then A4, A5, and A7; preserve explicit REQUIRED_UNSUPPORTED "
                "outcomes for A6/A8 unless their dependencies become real"
            ),
            "required": True,
            "forbidden_shortcuts": [
                "do not count component availability as production integration",
                "do not convert REQUIRED_UNSUPPORTED into PASS",
                "do not treat calibration integration as prospective evidence",
                "do not mount or execute validation-v6 before authorization"
            ]
        },
        "interpretation": (
            "The shared receipt overlay closes the multi-artifact accounting "
            "gap without modifying the frozen v1 contract. A3 and A9 now "
            "have complete, independently verified, process-tree-metered "
            "calibration batches, advancing integrated truth from two to "
            "four required arms. P3 still requires explicit outcomes for "
            "the other six arms, and P1 remains independently open."
        )
    }
    OUTPUT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_READINESS_ITERATION_4_6"
        " verdict=FOUNDRY_V6_NOT_READY"
        " prerequisites=4/6"
        " integrated=4/10"
        " shared_receipts=PASS"
        " prospective=false"
    )


if __name__ == "__main__":
    run()
