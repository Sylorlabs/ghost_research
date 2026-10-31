#!/usr/bin/env python3
"""Meter the A7 runtime mount and conformance under process-tree ceilings."""

from __future__ import annotations

import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULT = HERE / "results/phase142_a7_enumo_runtime_resource_audit.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def main() -> None:
    python = pathlib.Path(sys.executable).resolve()
    meter_test = selftest(str(python), ROOT)
    limits = {
        "wall_limit_seconds": 90,
        "cpu_limit_seconds": 75,
        "rss_limit_kib": 4_500_000,
    }
    environment = {
        "PYTHONWARNINGS": "ignore",
        "RAYON_NUM_THREADS": "1",
        "TORCHINDUCTOR_COMPILE_THREADS": "1",
        "OMP_NUM_THREADS": "1",
        "MKL_NUM_THREADS": "1",
    }
    mount = run_metered_tree(
        [
            str(python),
            str(HERE / "a7_enumo_runtime_mount.py"),
            "--summary-only",
        ],
        cwd=HERE,
        environment=environment,
        **limits,
    )
    mount_summary = json.loads(mount["stdout_text"])
    conformance = run_metered_tree(
        [
            str(python),
            str(HERE / "phase141_a7_enumo_runtime_conformance.py"),
        ],
        cwd=HERE,
        environment=environment,
        **limits,
    )
    conformance["expected_status_seen"] = (
        "FOUNDRY_PHASE141_A7_ENUMO_RUNTIME" in conformance["stdout_text"]
        and "graphs=23" in conformance["stdout_text"]
        and "unique=12" in conformance["stdout_text"]
        and "rewrite_checks=36" in conformance["stdout_text"]
        and "integrated=6/10" in conformance["stdout_text"]
    )
    receipts = [mount, conformance]
    checks = {
        "meter_hostile_selftest": meter_test["pass"],
        "identical_declared_ceilings": True,
        "mount_natural": (
            mount["returncode"] == 0 and mount["termination"] == "natural"
        ),
        "conformance_natural": (
            conformance["returncode"] == 0
            and conformance["termination"] == "natural"
            and conformance["expected_status_seen"]
        ),
        "mount_summary_exact": (
            mount_summary["status"]
            == "A7_ENUMO_RUNTIME_MOUNT_COMPONENT_PASS"
            and mount_summary["summary"]["graphs"] == 23
            and mount_summary["summary"]["call_function_invocations"] == 337
            and mount_summary["summary"]["eligible_calls"] == 53
            and mount_summary["summary"]["learned_root_matches"] == 282
            and mount_summary["summary"]["raw_selected_rule_applications"] == 24
            and mount_summary["summary"]["unique_selected_transformations"] == 12
            and mount_summary["summary"]["whole_graph_executions"] == 69
            and mount_summary["summary"]["unique_rewrite_concrete_checks"] == 36
            and mount_summary["summary"]["maximum_absolute_error"] == 0.0
        ),
        "all_process_CPU_charged": all(
            row["rusage_user_cpu_ns"] + row["rusage_system_cpu_ns"] > 0
            for row in receipts
        ),
        "all_process_RSS_sampled": all(
            row["peak_group_rss_kib"] > 0 for row in receipts
        ),
        "all_process_groups_reaped": all(
            row["process_group_reaped"] for row in receipts
        ),
        "integration_not_inflated": mount_summary["integration"][
            "A7_production_integrated"
        ]
        is False,
        "validation_v6_unread": mount_summary["validation_v6_accessed"] is False,
    }
    if not all(checks.values()):
        raise RuntimeError(
            "A7 runtime resource audit failed: "
            + canonical({"failed": [key for key, value in checks.items() if not value]})
        )
    payload = {
        "version": "FOUNDRY_A7_ENUMO_RUNTIME_RESOURCE_AUDIT_V1",
        "status": "A7_ENUMO_RUNTIME_RESOURCE_COMPONENT_PASS",
        "limits": limits,
        "meter_selftest": meter_test,
        "mount_receipt": mount,
        "mount_summary": mount_summary,
        "conformance_receipt": conformance,
        "checks": checks,
        "integration": {
            "A7_complete_mount_process_tree_metered": True,
            "A7_contract_batch_ready": False,
            "A7_production_integrated": False,
            "production_integrated_arms": 6,
        },
        "P3": {"complete": False},
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE142_A7_ENUMO_RUNTIME_RESOURCE"
        " status=A7_ENUMO_RUNTIME_RESOURCE_COMPONENT_PASS"
        " mount=PASS conformance=PASS unique=12"
        " integrated=6/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    main()
