#!/usr/bin/env python3
"""Process-tree accounting for the diversity candidate construction matrix."""

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
            "diversity_forge",
            "phase55_diversity_tool_forge.py",
            "FOUNDRY_PHASE55_DIVERSITY_TOOL_FORGE_PASS",
            120,
            100,
            4_500_000,
        ),
        (
            "independent_diversity_conformance",
            "phase56_independent_diversity_conformance.py",
            "FOUNDRY_PHASE56_INDEPENDENT_DIVERSITY_CONFORMANCE",
            150,
            120,
            4_500_000,
        ),
        (
            "diversity_native_dedup",
            "phase57_diversity_native_dedup.py",
            "FOUNDRY_PHASE57_DIVERSITY_NATIVE_DEDUP_PASS",
            300,
            240,
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
        "all_three_arms_executed": len(arms) == 3,
        "all_arms_natural": len(arms) == 3
        and all(
            row["returncode"] == 0 and row["termination"] == "natural"
            for row in arms.values()
        ),
        "all_statuses_bound": len(arms) == 3
        and all(row["expected_status_seen"] for row in arms.values()),
        "all_cpu_charged": len(arms) == 3
        and all(
            row["rusage_user_cpu_ns"] + row["rusage_system_cpu_ns"] > 0
            for row in arms.values()
        ),
        "all_rss_sampled": len(arms) == 3
        and all(
            row["peak_group_rss_kib"] > 0 for row in arms.values()
        ),
        "all_groups_reaped": len(arms) == 3
        and all(row["process_group_reaped"] for row in arms.values()),
    }
    passed = all(gates.values())
    payload = {
        "version": "FOUNDRY_DIVERSITY_RESOURCE_AUDIT_V1",
        "status": (
            "DIVERSITY_RESOURCE_COMPONENT_READY"
            if passed
            else "DIVERSITY_RESOURCE_COMPONENT_FAIL"
        ),
        "meter_selftest": meter_test,
        "arms": arms,
        "gates": gates,
        "validation_source_or_runtime_accessed": False,
    }
    (RESULTS / "phase58_diversity_resource_audit.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE58_DIVERSITY_RESOURCE"
        f" status={payload['status']}"
        f" arms={len(arms)}/3"
    )


if __name__ == "__main__":
    run()
