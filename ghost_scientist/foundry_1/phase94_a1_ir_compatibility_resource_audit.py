#!/usr/bin/env python3
"""Meter the frozen A1 IR compatibility audit under process-tree ceilings."""

from __future__ import annotations

import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULT = HERE / "results/phase94_a1_ir_compatibility_resource_audit.json"


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
    receipt = run_metered_tree(
        [
            str(python),
            str(HERE / "phase93_a1_ir_compatibility_audit.py"),
        ],
        cwd=HERE,
        wall_limit_seconds=limits["wall_limit_seconds"],
        cpu_limit_seconds=limits["cpu_limit_seconds"],
        rss_limit_kib=limits["rss_limit_kib"],
        environment={"PYTHONWARNINGS": "ignore"},
    )
    receipt["expected_status_seen"] = (
        "FOUNDRY_PHASE93_A1_IR_COMPATIBILITY" in receipt["stdout_text"]
        and "runtime_ops=22" in receipt["stdout_text"]
        and "mapped_targets=9/41" in receipt["stdout_text"]
        and "direct_calls=143/337" in receipt["stdout_text"]
        and "whole_graphs=4/23" in receipt["stdout_text"]
        and "patterns=0" in receipt["stdout_text"]
    )
    audit = json.loads(
        (
            HERE / "results/phase93_a1_ir_compatibility_audit.json"
        ).read_text()
    )
    checks = {
        "meter_hostile_selftest": meter_test["pass"],
        "natural_termination": (
            receipt["returncode"] == 0
            and receipt["termination"] == "natural"
        ),
        "status_bound": receipt["expected_status_seen"],
        "cpu_charged": (
            receipt["rusage_user_cpu_ns"]
            + receipt["rusage_system_cpu_ns"]
            > 0
        ),
        "rss_sampled": receipt["peak_group_rss_kib"] > 0,
        "process_group_reaped": receipt["process_group_reaped"],
        "complete_surface_preserved": (
            audit["summary"]["graphs"] == 23
            and audit["summary"]["unique_operator_targets"] == 41
            and audit["summary"]["call_function_invocations"] == 337
        ),
        "incomplete_surface_preserved": (
            audit["summary"]["whole_graph_direct"] == 4
            and audit["summary"]["exact_constructor_pattern_candidates"]
            == 0
            and audit["summary"]["production_adapter_ready"] is False
        ),
        "integration_not_inflated": audit["integration"][
            "production_integrated_arms"
        ]
        == 4,
        "validation_v6_unread": audit["validation_v6_accessed"] is False,
    }
    if not all(checks.values()):
        raise RuntimeError(
            "A1 compatibility resource audit failed: "
            + canonical(
                {
                    "failed": [
                        name for name, passed in checks.items() if not passed
                    ]
                }
            )
        )
    payload = {
        "version": "FOUNDRY_A1_IR_COMPATIBILITY_RESOURCE_AUDIT_V1",
        "status": "A1_IR_COMPATIBILITY_RESOURCE_PASS",
        "limits": limits,
        "meter_selftest": meter_test,
        "receipt": receipt,
        "checks": checks,
        "integration": {
            "A1_compatibility_audit_process_tree_metered": True,
            "A1_production_integrated": False,
            "production_integrated_arms": 4,
            "required_arms": 10,
        },
        "P3": {"complete": False},
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE94_A1_IR_COMPATIBILITY_RESOURCE"
        f" status={payload['status']}"
        " graphs=23 ops=41 calls=337"
        " A1_ready=false integrated=4/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    run()
