#!/usr/bin/env python3
"""Recompute readiness after rejecting the handwritten runtime route."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_pareto_remediation_v6 import verify as verify_remediation


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
PRIOR = RESULTS / "readiness_iteration_4_3.json"
OUTPUT = RESULTS / "readiness_iteration_4_4.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def run() -> None:
    freeze = verify_remediation()
    audit = json.loads(
        (
            RESULTS / "phase87_calibration_operator_vocabulary_audit.json"
        ).read_text()
    )
    resources = json.loads(
        (
            RESULTS
            / "phase88_calibration_operator_vocabulary_resource_audit.json"
        ).read_text()
    )
    if not (
        audit["status"]
        == "MANUAL_INTERPRETER_ROUTE_REJECTED_INCOMPLETE_SURFACE"
        and resources["status"] == "OPERATOR_VOCAB_ROUTE_RESOURCE_PASS"
        and freeze["required_runtime_route"]
        == "EVALUATOR_SIDE_FRAMEWORK_RUNTIME_MOUNT"
        and freeze["P3_complete"] is False
        and freeze["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("readiness 4.4 evidence invalid")
    summary = audit["summary"]
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_4_4",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": sha(PRIOR),
        "remediation_freeze_sha256": sha(
            RESULTS / "pareto_remediation_v6_freeze.json"
        ),
        "progress": {
            "P2_complete": True,
            "arm_adapter_contract_ready": True,
            "A3_A9_bounded_adapter_ready": True,
            "calibration_operator_surface_audited": True,
            "calibration_graphs": summary["graphs"],
            "calibration_unique_operators": summary["unique_operators"],
            "calibration_call_function_invocations": summary[
                "call_function_invocations"
            ],
            "bounded_unique_operators": summary[
                "bounded_unique_operators"
            ],
            "bounded_invocations": summary["bounded_invocations"],
            "manual_interpreter_production_ready": False,
            "required_runtime_route": audit["decision"]["required_route"],
            "runtime_route_audit_process_tree_metered": True,
            "framework_runtime_mount_implemented": False,
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
            "the evaluator-side framework runtime mount is selected but not implemented",
            "A1 and A3-A9 are not all complete behind the runtime mount and frozen contract",
            "all ten required arm paths are not process-tree metered under matched ceilings",
            "zero candidate runtime inventions survive native deduplication and the final measured-search distinction remains unregistered",
        ],
        "remediation": {
            "next_action": (
                "define a hash-bound evaluator runtime-mount interface, "
                "conformance-test it across all 23 calibration graphs and 41 "
                "observed operators, and keep graph/runtime mounting disabled "
                "for validation-v6 until authorization"
            ),
            "required": True,
            "forbidden_shortcuts": [
                "do not hand-implement only frequent operators and call the surface complete",
                "do not use structural expected outputs in place of framework execution",
                "do not mount validation-v6 runtime before authorization",
                "do not count route selection as runtime implementation",
            ],
        },
        "interpretation": (
            "The bounded interpreter reaches only 3 of 41 real calibration "
            "operators and 53 of 337 call-function invocations. The "
            "production requirement is complete surface coverage, so the "
            "manual route is rejected. The scientifically justified next "
            "implementation is an evaluator-owned framework runtime mount, "
            "not another growing handwritten proxy."
        ),
    }
    OUTPUT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_READINESS_ITERATION_4_4"
        " verdict=FOUNDRY_V6_NOT_READY"
        " prerequisites=4/6"
        " integrated=2/10"
        " route=FRAMEWORK_MOUNT"
        " prospective=false"
    )


if __name__ == "__main__":
    run()
