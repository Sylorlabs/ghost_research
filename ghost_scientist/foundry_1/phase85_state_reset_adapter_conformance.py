#!/usr/bin/env python3
"""End-to-end conformance for bounded A3/A9 typed-DAG adapters."""

from __future__ import annotations

import copy
import json
import math
import pathlib

from arm_adapter_contract import parse_input, parse_output
from independent_arm_adapter_contract import verify as verify_contract
from independent_state_reset_adapter import (
    IndependentStateResetReject,
    parse_and_run,
)
from state_reset_arm_adapter import EMPTY, run as run_adapter
from typed_dag_artifact import (
    TypedDagReject,
    canonical,
    covered_nodes,
    enumerate_groups,
    execute,
    max_error,
    parse,
    select,
)


HERE = pathlib.Path(__file__).resolve().parent
FIXTURES = HERE / "arm_adapter_fixtures"
RESULT = HERE / "results/phase85_state_reset_adapter_conformance.json"


def rejected_twice(mutated: dict, arm_id: str = "A3") -> bool:
    raw = canonical(mutated)
    primary_reject = independent_reject = False
    try:
        artifact = parse(raw)
        errors = [
            max_error(
                execute(artifact, invocation),
                invocation["expected_outputs"],
            )
            for invocation in artifact["invocations"]
        ]
        if not errors or max(errors) > 1.0e-12:
            raise TypedDagReject("semantic mismatch")
    except (TypedDagReject, ValueError, KeyError, TypeError):
        primary_reject = True
    try:
        receipt = parse_and_run(raw, arm_id)
        if receipt["max_abs_error"] > 1.0e-12:
            raise IndependentStateResetReject("semantic mismatch")
    except (
        IndependentStateResetReject,
        ValueError,
        KeyError,
        TypeError,
    ):
        independent_reject = True
    return primary_reject and independent_reject


def run() -> None:
    protocol = json.loads(
        (FIXTURES / "STATE_RESET_TYPED_DAG_PROTOCOL_V1.json").read_text()
    )
    raw_artifact = (
        FIXTURES / "state_reset_typed_dag_v1.json"
    ).read_bytes()
    artifact = parse(raw_artifact)
    groups, paths = enumerate_groups(artifact)
    arm_rows = {}
    for arm_id in ("A3", "A9"):
        raw_request = (
            FIXTURES / f"state_reset_{arm_id}_input_v1.json"
        ).read_bytes()
        request = parse_input(raw_request)
        response = run_adapter(raw_request, raw_artifact)
        raw_response = canonical(response)
        parse_output(raw_response, request)
        contract_receipt = verify_contract(raw_request, raw_response)
        independent = parse_and_run(raw_artifact, arm_id)
        selected = select(groups, arm_id)
        arm_rows[arm_id] = {
            "status": response["status"],
            "contract_receipt": contract_receipt,
            "state_policy": response["state_policy"],
            "tool_receipts": response["tool_receipts"],
            "cost_ledger": response["cost_ledger"],
            "correctness": response["correctness"],
            "resources": response["resources"],
            "motifs": {
                "paths_enumerated": paths,
                "exact_typed_body_groups": len(groups),
                "search_construction_units": paths + len(groups),
                "tools_selected": len(selected),
                "unique_nodes_covered": len(covered_nodes(selected)),
            },
            "independent": independent,
        }
    hostile = []

    def attack(name: str, mutate) -> None:
        mutated = copy.deepcopy(artifact)
        mutate(mutated)
        hostile.append(
            {"name": name, "rejected_twice": rejected_twice(mutated)}
        )

    attack("extra_artifact_field", lambda value: value.update(leak=True))
    attack(
        "unknown_operation",
        lambda value: value["nodes"][0].update(op="mystery"),
    )
    attack(
        "forward_dependency_cycle",
        lambda value: value["nodes"][0].update(args=["n8", "y"]),
    )
    attack(
        "type_shape_mismatch",
        lambda value: value["nodes"][0]["type"].update(shape=[5]),
    )
    attack(
        "changed_expected_output",
        lambda value: value["invocations"][0]["expected_outputs"][0].__setitem__(
            0, 2.75
        ),
    )
    attack(
        "missing_invocation",
        lambda value: value["invocations"].pop(),
    )
    attack(
        "wrong_invocation_ordinal",
        lambda value: value["invocations"][1].update(ordinal=3),
    )
    attack(
        "nonfinite_expected_output",
        lambda value: value["invocations"][0]["expected_outputs"][0].__setitem__(
            0, math.nan
        ),
    )
    attack(
        "unknown_output",
        lambda value: value.update(outputs=["not_a_node"]),
    )
    a3 = arm_rows["A3"]
    a9 = arm_rows["A9"]
    checks = {
        "protocol_prefrozen": protocol[
            "frozen_before_adapter_execution"
        ],
        "artifact_primary_parser_accepts": artifact["artifact_id"]
        == "state-reset-repeated-add-relu-v1",
        "both_contract_outputs_PASS": (
            a3["status"] == a9["status"] == "PASS"
        ),
        "both_contract_verifiers_accept": (
            a3["contract_receipt"]["status"]
            == a9["contract_receipt"]["status"]
            == "PASS"
        ),
        "both_interpreters_exact_three_times": (
            a3["correctness"]["max_abs_error"]
            == a9["correctness"]["max_abs_error"]
            == a3["independent"]["max_abs_error"]
            == a9["independent"]["max_abs_error"]
            == 0.0
            and len(a3["correctness"]["invocation_receipts"])
            == len(a9["correctness"]["invocation_receipts"])
            == 3
        ),
        "primary_independent_motif_counts_agree": (
            a3["motifs"]["paths_enumerated"]
            == a3["independent"]["paths"]
            == a9["motifs"]["paths_enumerated"]
            == a9["independent"]["paths"]
            and a3["motifs"]["exact_typed_body_groups"]
            == a3["independent"]["groups"]
            == a9["motifs"]["exact_typed_body_groups"]
            == a9["independent"]["groups"]
        ),
        "A3_only_repeated_positive_MDL": a3["independent"][
            "all_selected_repeated_positive_mdl"
        ]
        is True,
        "A9_coverage_not_below_A3": (
            a9["motifs"]["unique_nodes_covered"]
            >= a3["motifs"]["unique_nodes_covered"]
        ),
        "both_states_empty_before_after": all(
            row["state_policy"]["state_before_sha256"]
            == row["state_policy"]["state_after_sha256"]
            == EMPTY
            and row["state_policy"]["library_retained_across_artifacts"]
            is False
            for row in arm_rows.values()
        ),
        "both_CPU_ledgers_sum": all(
            row["cost_ledger"]["total_cpu_ns"]
            == sum(
                value
                for key, value in row["cost_ledger"].items()
                if key != "total_cpu_ns"
            )
            and row["cost_ledger"]["total_cpu_ns"] > 0
            for row in arm_rows.values()
        ),
        "nine_hostile_artifacts_rejected_twice": (
            len(hostile) == 9
            and all(row["rejected_twice"] for row in hostile)
        ),
        "integration_truth_not_inflated": protocol["claim_boundary"][
            "production_integrated_arms_after_pass"
        ]
        == 2,
        "validation_v6_unread": protocol["claim_boundary"][
            "validation_v6_source_runtime_graph_or_outcome_accessed"
        ]
        is False,
        "prospective_unauthorized": protocol["claim_boundary"][
            "prospective_trial_authorized"
        ]
        is False,
    }
    if not all(checks.values()):
        raise RuntimeError(
            "state-reset adapter conformance failed: "
            + json.dumps(
                {
                    "failed": [
                        name for name, passed in checks.items() if not passed
                    ],
                    "hostile": hostile,
                    "A3": a3["motifs"],
                    "A9": a9["motifs"],
                },
                sort_keys=True,
            )
        )
    payload = {
        "version": "FOUNDRY_STATE_RESET_ADAPTER_CONFORMANCE_V1",
        "status": "STATE_RESET_ADAPTER_BOUNDED_CONFORMANCE_PASS",
        "classification": (
            "A3_A9_TYPED_DAG_INTERFACE_READY_NOT_VALIDATION_V6_INTEGRATED"
        ),
        "checks": checks,
        "arms": arm_rows,
        "hostile_rejections": hostile,
        "integration": {
            "A3_typed_dag_adapter_implemented": True,
            "A9_typed_dag_adapter_implemented": True,
            "full_validation_operator_surface_tested": False,
            "runtime_mount_integration_tested": False,
            "production_integrated_arms": 2,
            "required_arms": 10,
        },
        "P3": {
            "A3_A9_bounded_adapter_component_ready": True,
            "A3_A9_production_integrated": False,
            "all_required_prospective_arms_metered": False,
            "complete": False,
        },
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload).decode() + "\n")
    print(
        "FOUNDRY_PHASE85_STATE_RESET_ADAPTER"
        f" status={payload['status']}"
        f" paths={a3['motifs']['paths_enumerated']}"
        f" groups={a3['motifs']['exact_typed_body_groups']}"
        f" tools={a3['motifs']['tools_selected']}/"
        f"{a9['motifs']['tools_selected']}"
        f" coverage={a3['motifs']['unique_nodes_covered']}/"
        f"{a9['motifs']['unique_nodes_covered']}"
        " hostile=9/9 integrated=2/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    run()
