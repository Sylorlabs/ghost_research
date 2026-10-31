#!/usr/bin/env python3
"""Recompute readiness after bounded A3/A9 adapter implementation."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_pareto_remediation_v5 import verify as verify_remediation


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
PRIOR = RESULTS / "readiness_iteration_4_2.json"
OUTPUT = RESULTS / "readiness_iteration_4_3.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def run() -> None:
    freeze = verify_remediation()
    conformance = json.loads(
        (
            RESULTS / "phase85_state_reset_adapter_conformance.json"
        ).read_text()
    )
    resources = json.loads(
        (
            RESULTS / "phase86_state_reset_adapter_resource_audit.json"
        ).read_text()
    )
    if not (
        conformance["status"]
        == "STATE_RESET_ADAPTER_BOUNDED_CONFORMANCE_PASS"
        and resources["status"]
        == "STATE_RESET_ADAPTER_RESOURCE_COMPONENT_PASS"
        and freeze["P3_complete"] is False
        and freeze["production_integrated_arms"] == 2
        and freeze["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("readiness 4.3 evidence invalid")
    a3 = conformance["arms"]["A3"]["motifs"]
    a9 = conformance["arms"]["A9"]["motifs"]
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_4_3",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": sha(PRIOR),
        "remediation_freeze_sha256": sha(
            RESULTS / "pareto_remediation_v5_freeze.json"
        ),
        "progress": {
            "P2_complete": True,
            "arm_adapter_contract_ready": True,
            "A3_bounded_typed_dag_adapter_ready": True,
            "A9_bounded_typed_dag_adapter_ready": True,
            "artifact_parsers": 2,
            "artifact_interpreters": 2,
            "exact_invocations_per_arm": 3,
            "hostile_artifacts_rejected_twice": 9,
            "bounded_operator_count": 3,
            "shared_search_construction_units": a3[
                "search_construction_units"
            ],
            "A3_tools_selected": a3["tools_selected"],
            "A9_tools_selected": a9["tools_selected"],
            "A3_unique_nodes_covered": a3["unique_nodes_covered"],
            "A9_unique_nodes_covered": a9["unique_nodes_covered"],
            "A3_A9_process_tree_metered": True,
            "validation_operator_surface_complete": False,
            "runtime_mount_integration_complete": False,
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
            "the bounded A3/A9 add-mul-relu adapter does not cover the validation operator surface or real runtime mount",
            "A1, A4, A5, A6, A7, and A8 still lack complete adapters behind the frozen contract",
            "all ten required adapter paths are not process-tree metered under matched ceilings",
            "zero candidate runtime inventions survive native deduplication and the final measured-search distinction remains unregistered",
        ],
        "remediation": {
            "next_action": (
                "derive the allowed typed operator vocabulary from calibration "
                "and already-frozen protocol evidence only, generalize the "
                "artifact interpreter and A3/A9 adapters to that vocabulary, "
                "and test an evaluator-side runtime mount without opening "
                "validation-v6"
            ),
            "required": True,
            "forbidden_shortcuts": [
                "do not call three primitive operators the validation surface",
                "do not count structural replay as a real runtime mount",
                "do not count bounded interface readiness as production integration",
                "do not let A3 or A9 retain cross-artifact state",
                "do not open validation-v6 before a new authorization pass",
            ],
        },
        "interpretation": (
            "A3 and A9 now genuinely execute behind the frozen contract on "
            "an evaluator-owned typed DAG. Two parsers and interpreters agree "
            "on three numerical executions, motif counts, and coverage; nine "
            "hostile artifacts fail twice; both process trees are metered. "
            "The operator surface is deliberately only add, mul, and relu, "
            "so this is an interface implementation, not validation-v6 "
            "production integration."
        ),
    }
    OUTPUT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_READINESS_ITERATION_4_3"
        " verdict=FOUNDRY_V6_NOT_READY"
        " prerequisites=4/6"
        " integrated=2/10"
        " A3_A9=BOUNDED_READY"
        " prospective=false"
    )


if __name__ == "__main__":
    run()
