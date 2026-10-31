#!/usr/bin/env python3
"""Recompute readiness after A3/A9 kernel and resource remediation."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_pareto_remediation_v1 import verify as verify_remediation


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
PRIOR = RESULTS / "readiness_iteration_3_8.json"
OUTPUT = RESULTS / "readiness_iteration_3_9.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def run() -> None:
    freeze = verify_remediation()
    controls = json.loads(
        (RESULTS / "phase72_per_instance_control_conformance.json").read_text()
    )
    resources = json.loads(
        (RESULTS / "phase73_per_instance_resource_audit.json").read_text()
    )
    if not (
        controls["status"]
        == "PER_INSTANCE_CONTROL_KERNELS_CONFORMANCE_PASS"
        and resources["status"]
        == "PER_INSTANCE_CONTROL_RESOURCE_COMPONENT_READY"
        and freeze["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("A3/A9 readiness evidence invalid")
    a3 = controls["A3"]["summary"]
    a9 = controls["A9"]["summary"]
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_3_9",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": sha(PRIOR),
        "remediation_freeze_sha256": sha(
            RESULTS / "pareto_remediation_v1_freeze.json"
        ),
        "control_conformance_sha256": sha(
            RESULTS / "phase72_per_instance_control_conformance.json"
        ),
        "control_resource_sha256": sha(
            RESULTS / "phase73_per_instance_resource_audit.json"
        ),
        "progress": {
            "A3_calibration_conformance": True,
            "A9_calibration_conformance": True,
            "A3_calibration_metered": True,
            "A9_calibration_metered": True,
            "equal_search_construction_units": a3[
                "search_construction_units"
            ]
            == a9["search_construction_units"]
            == 969,
            "state_reset_local_group_overhead_vs_A2": 49,
            "A3_unique_nodes_covered": a3["unique_nodes_covered"],
            "A9_unique_nodes_covered": a9["unique_nodes_covered"],
            "A3_production_integrated": False,
            "A9_production_integrated": False,
            "heldout_source_runtime_or_graph_accessed": False,
        },
        "prerequisites": {
            "P1_external_control_conformance": False,
            "P2_independent_corpus_and_invocation_trace": False,
            "P3_complete_resource_meter": False,
            "P4_independent_typed_tool_verifier": True,
            "P5_native_compiler_deduplication": True,
            "P6_unchanged_prospective_freeze": True,
        },
        "authorization": {
            "prerequisites_passed": 3,
            "prerequisites_required": 6,
            "required_arms_production_integrated": 2,
            "required_arms": 10,
            "active_stop_conditions": 2,
            "prospective_trial_authorized": False,
        },
        "remaining_blockers": [
            "A8 remains only a paper-derived partial boundary, not a full strategy-synthesis control",
            "A1 and A3-A9 are not all integrated behind one frozen prospective runner",
            "A4-A8 do not all have complete process-tree prospective resource paths",
            "no independent deployment-demand trace freezes N*",
            "zero candidate runtime inventions survive native deduplication"
        ],
        "remediation": {
            "next_action": (
                "define one evaluator-owned arm adapter contract and integrate "
                "A1 plus A3-A9 without reading validation-v6; separately "
                "continue official EggMind and invocation-trace acquisition"
            ),
            "required": True,
            "forbidden_shortcuts": [
                "do not count calibration kernel conformance as prospective integration",
                "do not call the EqSatL boundary EggMind",
                "do not equalize compute by deleting observed rediscovery overhead",
                "do not open validation-v6 before a new authorization pass"
            ],
        },
        "interpretation": (
            "The no-library and per-instance controls now execute from empty "
            "state under identical ceilings. Empty-state rediscovery costs 49 "
            "more grouping units than persistent global deduplication, while "
            "per-instance search covers more calibration nodes. These are "
            "useful control mechanics, not a prospective result."
        ),
    }
    OUTPUT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_READINESS_ITERATION_3_9"
        " verdict=FOUNDRY_V6_NOT_READY"
        " prerequisites=3/6"
        " integrated=2/10"
        " prospective=false"
    )


if __name__ == "__main__":
    run()
