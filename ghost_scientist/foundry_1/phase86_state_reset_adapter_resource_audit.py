#!/usr/bin/env python3
"""Meter bounded A3/A9 adapters under identical process-tree ceilings."""

from __future__ import annotations

import json
import pathlib
import sys

from arm_adapter_contract import parse_input, parse_output
from independent_arm_adapter_contract import verify as verify_contract
from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
FIXTURES = HERE / "arm_adapter_fixtures"
RESULT = HERE / "results/phase86_state_reset_adapter_resource_audit.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def run() -> None:
    python = pathlib.Path(sys.executable).resolve()
    meter_test = selftest(str(python), ROOT)
    limits = {
        "wall_limit_seconds": 20,
        "cpu_limit_seconds": 15,
        "rss_limit_kib": 524288,
    }
    conformance = run_metered_tree(
        [
            str(python),
            str(HERE / "phase85_state_reset_adapter_conformance.py"),
        ],
        cwd=HERE,
        wall_limit_seconds=limits["wall_limit_seconds"],
        cpu_limit_seconds=limits["cpu_limit_seconds"],
        rss_limit_kib=limits["rss_limit_kib"],
        environment={"PYTHONWARNINGS": "ignore"},
    )
    conformance["expected_status_seen"] = (
        "FOUNDRY_PHASE85_STATE_RESET_ADAPTER"
        in conformance["stdout_text"]
        and "hostile=9/9" in conformance["stdout_text"]
        and "integrated=2/10" in conformance["stdout_text"]
    )
    arms = {}
    for arm_id in ("A3", "A9"):
        request_path = (
            FIXTURES / f"state_reset_{arm_id}_input_v1.json"
        )
        receipt = run_metered_tree(
            [
                str(python),
                str(HERE / "state_reset_arm_adapter.py"),
                "--request",
                str(request_path),
                "--artifact",
                str(FIXTURES / "state_reset_typed_dag_v1.json"),
            ],
            cwd=HERE,
            wall_limit_seconds=limits["wall_limit_seconds"],
            cpu_limit_seconds=limits["cpu_limit_seconds"],
            rss_limit_kib=limits["rss_limit_kib"],
            environment={"PYTHONWARNINGS": "ignore"},
        )
        response = json.loads(receipt["stdout_text"])
        request_raw = request_path.read_bytes()
        request = parse_input(request_raw)
        parse_output(
            json.dumps(
                response, sort_keys=True, separators=(",", ":")
            ).encode(),
            request,
        )
        independent = verify_contract(
            request_raw,
            json.dumps(
                response, sort_keys=True, separators=(",", ":")
            ).encode(),
        )
        receipt["contract_status"] = response["status"]
        receipt["contract_independent_status"] = independent["status"]
        receipt["inner_total_cpu_ns"] = response["cost_ledger"][
            "total_cpu_ns"
        ]
        receipt["inner_invocations"] = len(
            response["correctness"]["invocation_receipts"]
        )
        receipt["inner_state_reset"] = (
            response["state_policy"]["state_before_sha256"]
            == response["state_policy"]["state_after_sha256"]
            and response["state_policy"][
                "library_retained_across_artifacts"
            ]
            is False
        )
        arms[arm_id] = receipt
    phase85 = json.loads(
        (HERE / "results/phase85_state_reset_adapter_conformance.json").read_text()
    )
    checks = {
        "meter_hostile_selftest": meter_test["pass"],
        "identical_declared_ceilings": True,
        "conformance_natural": (
            conformance["returncode"] == 0
            and conformance["termination"] == "natural"
            and conformance["expected_status_seen"]
        ),
        "both_arms_natural": all(
            row["returncode"] == 0 and row["termination"] == "natural"
            for row in arms.values()
        ),
        "both_contract_verifiers_PASS": all(
            row["contract_status"]
            == row["contract_independent_status"]
            == "PASS"
            for row in arms.values()
        ),
        "both_execute_three_invocations": all(
            row["inner_invocations"] == 3 for row in arms.values()
        ),
        "both_state_reset": all(
            row["inner_state_reset"] for row in arms.values()
        ),
        "both_inner_CPU_ledgers_nonzero": all(
            row["inner_total_cpu_ns"] > 0 for row in arms.values()
        ),
        "all_process_CPU_charged": all(
            row["rusage_user_cpu_ns"] + row["rusage_system_cpu_ns"] > 0
            for row in [conformance, *arms.values()]
        ),
        "all_process_RSS_sampled": all(
            row["peak_group_rss_kib"] > 0
            for row in [conformance, *arms.values()]
        ),
        "all_process_groups_reaped": all(
            row["process_group_reaped"]
            for row in [conformance, *arms.values()]
        ),
        "same_search_construction_units": (
            phase85["arms"]["A3"]["motifs"]["search_construction_units"]
            == phase85["arms"]["A9"]["motifs"][
                "search_construction_units"
            ]
            == 21
        ),
        "integration_not_inflated": phase85["integration"][
            "production_integrated_arms"
        ]
        == 2,
        "validation_v6_unread": phase85["validation_v6_accessed"] is False,
    }
    if not all(checks.values()):
        raise RuntimeError("state-reset adapter resource audit failed")
    payload = {
        "version": "FOUNDRY_STATE_RESET_ADAPTER_RESOURCE_AUDIT_V1",
        "status": "STATE_RESET_ADAPTER_RESOURCE_COMPONENT_PASS",
        "limits": limits,
        "meter_selftest": meter_test,
        "conformance_receipt": conformance,
        "arms": arms,
        "checks": checks,
        "P3": {
            "A3_bounded_adapter_process_tree_metered": True,
            "A9_bounded_adapter_process_tree_metered": True,
            "A3_A9_production_operator_surface_complete": False,
            "all_required_prospective_arms_metered": False,
            "complete": False,
        },
        "production_integrated_arms": 2,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE86_STATE_RESET_ADAPTER_RESOURCE"
        f" status={payload['status']}"
        " arms=2/2 search=21/21"
        " integrated=2/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    run()
