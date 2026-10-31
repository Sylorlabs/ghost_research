#!/usr/bin/env python3
"""Recompute readiness after the calibration framework mount passes."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_pareto_remediation_v7 import verify as verify_remediation


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
PRIOR = RESULTS / "readiness_iteration_4_4.json"
OUTPUT = RESULTS / "readiness_iteration_4_5.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def run() -> None:
    freeze = verify_remediation()
    mount = json.loads(
        (
            RESULTS / "phase89_framework_runtime_mount_conformance.json"
        ).read_text()
    )
    resources = json.loads(
        (
            RESULTS
            / "phase90_framework_runtime_mount_resource_audit.json"
        ).read_text()
    )
    if not (
        mount["status"] == "FRAMEWORK_RUNTIME_MOUNT_COMPONENT_PASS"
        and resources["status"]
        == "FRAMEWORK_RUNTIME_MOUNT_RESOURCE_COMPONENT_PASS"
        and freeze["A3_A9_runtime_mount_component_ready"] is True
        and freeze["P3_complete"] is False
        and freeze["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("readiness 4.5 evidence invalid")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_4_5",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": sha(PRIOR),
        "remediation_freeze_sha256": sha(
            RESULTS / "pareto_remediation_v7_freeze.json"
        ),
        "progress": {
            "P2_complete": True,
            "arm_adapter_contract_ready": True,
            "A3_A9_bounded_adapter_ready": True,
            "calibration_operator_surface_audited": True,
            "framework_runtime_mount_implemented": True,
            "framework_runtime_mount_component_ready": True,
            "calibration_graphs_mounted": 23,
            "calibration_unique_operators_executed": 41,
            "calibration_call_function_invocations_executed": 337,
            "framework_executions_per_arm": 69,
            "A3_A9_complete_mount_process_trees_metered": True,
            "per_artifact_contract_resource_assembly_ready": False,
            "production_integrated_arms": 2,
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
            "required_arms_production_integrated": 2,
            "required_arms": 10,
            "active_stop_conditions": 1,
            "prospective_trial_authorized": False,
        },
        "remaining_blockers": [
            "P1 still lacks the fourth complete source-faithful control",
            "the frozen arm contract has no shared resource-receipt identity for one process mounting multiple artifacts",
            "A1, A4, A5, and A7 are not adapted to the framework mount",
            "A6 and A8 remain required fail-closed arms with unavailable declared dependencies",
            "all ten required arm paths are not process-tree metered under matched ceilings",
            "zero candidate runtime inventions survive native deduplication and the final measured-search distinction remains unregistered"
        ],
        "remediation": {
            "next_action": (
                "freeze an additive shared-resource-receipt overlay, assemble "
                "complete A3/A9 contract outputs without double counting, "
                "then adapt A1, A4, A5, and A7 while P1 acquisition continues"
            ),
            "required": True,
            "forbidden_shortcuts": [
                "do not copy one arm-level process receipt into 23 artifact records",
                "do not edit the frozen v1 arm contract",
                "do not relabel the calibration mount as prospective integration",
                "do not mount or execute validation-v6 before authorization"
            ]
        },
        "interpretation": (
            "The selected evaluator-side framework route is now real on the "
            "complete calibration surface: both arms execute all 23 graphs "
            "and 41 observed operators with exact outputs under independent "
            "checks and complete arm-level process-tree metering. P3 remains "
            "open because its per-artifact contract assembly cannot yet "
            "reference one shared resource receipt without double counting, "
            "and only two of ten required arms are production-integrated."
        )
    }
    OUTPUT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_READINESS_ITERATION_4_5"
        " verdict=FOUNDRY_V6_NOT_READY"
        " prerequisites=4/6"
        " integrated=2/10"
        " framework_mount=PASS"
        " prospective=false"
    )


if __name__ == "__main__":
    run()
