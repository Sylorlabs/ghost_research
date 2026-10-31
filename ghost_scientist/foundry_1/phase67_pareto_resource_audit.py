#!/usr/bin/env python3
"""Process-tree accounting for the Pareto construction matrix."""

from __future__ import annotations

import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULTS = HERE / "results"


def run() -> None:
    python = pathlib.Path(sys.executable).resolve()
    meter_test = selftest(str(python), ROOT)
    arms = {}
    specifications = (
        (
            "pareto_motif_calibration",
            "phase63_pareto_motif_calibration.py",
            "FOUNDRY_PHASE63_PARETO_MOTIF_CALIBRATION_PASS",
            150,
            120,
            4_500_000,
        ),
        (
            "pareto_optimizer",
            "phase64_pareto_portfolio_optimizer.py",
            "FOUNDRY_PHASE64_PARETO_PORTFOLIO_OPTIMIZER_PASS",
            150,
            120,
            4_500_000,
        ),
        (
            "independent_pareto_conformance",
            "phase65_independent_pareto_conformance.py",
            "FOUNDRY_PHASE65_INDEPENDENT_PARETO_CONFORMANCE",
            180,
            150,
            4_500_000,
        ),
        (
            "pareto_native_dedup",
            "phase66_pareto_native_dedup.py",
            "FOUNDRY_PHASE66_PARETO_NATIVE_DEDUP_PASS",
            360,
            300,
            4_500_000,
        ),
    )
    for name, script, marker, wall, cpu, rss in specifications:
        receipt = run_metered_tree(
            [str(python), str(HERE / script)],
            cwd=HERE,
            wall_limit_seconds=wall,
            cpu_limit_seconds=cpu,
            rss_limit_kib=rss,
            environment={
                "TORCHINDUCTOR_COMPILE_THREADS": "1",
                "OMP_NUM_THREADS": "1",
                "MKL_NUM_THREADS": "1",
            },
        )
        receipt["expected_status_seen"] = marker in receipt["stdout_text"]
        arms[name] = receipt
        if (
            receipt["returncode"] != 0
            or receipt["termination"] != "natural"
            or not receipt["expected_status_seen"]
        ):
            break
    gates = {
        "meter_hostile_selftest": meter_test["pass"],
        "all_four_arms_executed": len(arms) == 4,
        "all_arms_natural": len(arms) == 4
        and all(
            row["returncode"] == 0 and row["termination"] == "natural"
            for row in arms.values()
        ),
        "all_statuses_bound": len(arms) == 4
        and all(row["expected_status_seen"] for row in arms.values()),
        "all_cpu_charged": len(arms) == 4
        and all(
            row["rusage_user_cpu_ns"] + row["rusage_system_cpu_ns"] > 0
            for row in arms.values()
        ),
        "all_rss_sampled": len(arms) == 4
        and all(
            row["peak_group_rss_kib"] > 0 for row in arms.values()
        ),
        "all_groups_reaped": len(arms) == 4
        and all(row["process_group_reaped"] for row in arms.values()),
    }
    passed = all(gates.values())
    payload = {
        "version": "FOUNDRY_PARETO_RESOURCE_AUDIT_V1",
        "status": (
            "PARETO_RESOURCE_COMPONENT_READY"
            if passed
            else "PARETO_RESOURCE_COMPONENT_FAIL"
        ),
        "meter_selftest": meter_test,
        "arms": arms,
        "gates": gates,
        "validation_v6_accessed": False,
    }
    (RESULTS / "phase67_pareto_resource_audit.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE67_PARETO_RESOURCE"
        f" status={payload['status']}"
        f" arms={len(arms)}/4"
    )


if __name__ == "__main__":
    run()
