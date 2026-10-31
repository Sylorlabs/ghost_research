#!/usr/bin/env python3
"""Meter the source-faithful A5 typed-graph Stitch execution."""

from __future__ import annotations

import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULT = (
    HERE / "results/phase100_a5_stitch_typed_graph_resource_audit.json"
)


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def main() -> None:
    python = pathlib.Path(sys.executable).resolve()
    meter_test = selftest(str(python), ROOT)
    limits = {
        "wall_limit_seconds": 90,
        "cpu_limit_seconds": 75,
        "rss_limit_kib": 4500000,
    }
    receipt = run_metered_tree(
        [
            str(python),
            str(HERE / "phase99_a5_stitch_typed_graph_audit.py"),
        ],
        cwd=HERE,
        wall_limit_seconds=limits["wall_limit_seconds"],
        cpu_limit_seconds=limits["cpu_limit_seconds"],
        rss_limit_kib=limits["rss_limit_kib"],
        environment={
            "PYTHONWARNINGS": "ignore",
            "RAYON_NUM_THREADS": "1",
            "OMP_NUM_THREADS": "1",
            "MKL_NUM_THREADS": "1",
        },
    )
    receipt["expected_status_seen"] = (
        "FOUNDRY_PHASE99_A5_STITCH_TYPED_GRAPH"
        in receipt["stdout_text"]
        and "graphs=23" in receipt["stdout_text"]
        and "ops=41" in receipt["stdout_text"]
        and "calls=337" in receipt["stdout_text"]
        and "abstractions=1" in receipt["stdout_text"]
        and "cost=452962/386504" in receipt["stdout_text"]
    )
    audit = json.loads(
        (
            HERE / "results/phase99_a5_stitch_typed_graph_audit.json"
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
            audit["input"]["programs"] == 23
            and audit["input"]["unique_operator_targets"] == 41
            and audit["input"]["call_function_invocations"] == 337
        ),
        "source_algorithm_result_preserved": (
            audit["status"] == "A5_STITCH_TYPED_GRAPH_COMPONENT_PASS"
            and audit["observed"]["abstractions"] == 1
            and audit["observed"]["original_cost"] == 452962
            and audit["observed"]["final_cost"] == 386504
            and audit["observed"]["cost_change"] == 66458
        ),
        "duplicate_program_multiplicity_preserved": (
            audit["input"]["unique_programs"] == 22
            and audit["input"]["duplicate_program_instances"] == 1
        ),
        "integration_not_inflated": audit["integration"][
            "production_integrated_arms"
        ]
        == 5
        and audit["integration"]["A5_production_integrated"] is False,
        "validation_v6_unread": audit["validation_v6_accessed"] is False,
    }
    if not all(checks.values()):
        raise RuntimeError(
            "A5 typed graph resource audit failed: "
            + canonical(
                {
                    "failed": [
                        name for name, passed in checks.items() if not passed
                    ]
                }
            )
        )
    payload = {
        "version": "FOUNDRY_A5_STITCH_TYPED_GRAPH_RESOURCE_AUDIT_V1",
        "status": "A5_STITCH_TYPED_GRAPH_RESOURCE_COMPONENT_PASS",
        "limits": limits,
        "meter_selftest": meter_test,
        "receipt": receipt,
        "checks": checks,
        "integration": {
            "A5_source_algorithm_process_tree_metered": True,
            "A5_framework_numerical_mount_ready": False,
            "A5_contract_batch_ready": False,
            "A5_production_integrated": False,
            "production_integrated_arms": 5,
        },
        "P3": {"complete": False},
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE100_A5_STITCH_TYPED_GRAPH_RESOURCE"
        f" status={payload['status']}"
        " graphs=23 abstractions=1 cost_change=66458"
        " integrated=5/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    main()
