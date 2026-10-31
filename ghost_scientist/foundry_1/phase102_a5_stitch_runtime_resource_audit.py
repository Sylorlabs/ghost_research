#!/usr/bin/env python3
"""Meter A5 mount and conformance under complete process-tree ceilings."""

from __future__ import annotations

import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULT = (
    HERE / "results/phase102_a5_stitch_runtime_resource_audit.json"
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
            str(HERE / "a5_stitch_runtime_mount.py"),
            "--summary-only",
        ],
        cwd=HERE,
        wall_limit_seconds=limits["wall_limit_seconds"],
        cpu_limit_seconds=limits["cpu_limit_seconds"],
        rss_limit_kib=limits["rss_limit_kib"],
        environment=environment,
    )
    mount_summary = json.loads(mount["stdout_text"])
    conformance = run_metered_tree(
        [
            str(python),
            str(HERE / "phase101_a5_stitch_runtime_conformance.py"),
        ],
        cwd=HERE,
        wall_limit_seconds=limits["wall_limit_seconds"],
        cpu_limit_seconds=limits["cpu_limit_seconds"],
        rss_limit_kib=limits["rss_limit_kib"],
        environment=environment,
    )
    conformance["expected_status_seen"] = (
        "FOUNDRY_PHASE101_A5_STITCH_RUNTIME"
        in conformance["stdout_text"]
        and "graphs=23" in conformance["stdout_text"]
        and "normalized=23/23" in conformance["stdout_text"]
        and "uses=329" in conformance["stdout_text"]
        and "integrated=5/10" in conformance["stdout_text"]
    )
    receipts = [mount, conformance]
    checks = {
        "meter_hostile_selftest": meter_test["pass"],
        "identical_declared_ceilings": True,
        "mount_natural": (
            mount["returncode"] == 0
            and mount["termination"] == "natural"
        ),
        "conformance_natural": (
            conformance["returncode"] == 0
            and conformance["termination"] == "natural"
            and conformance["expected_status_seen"]
        ),
        "mount_summary_exact": (
            mount_summary["status"]
            == "A5_STITCH_RUNTIME_MOUNT_COMPONENT_PASS"
            and mount_summary["rows"] == 23
            and mount_summary["summary"]["unique_operator_targets"] == 41
            and mount_summary["summary"]["call_function_invocations"] == 337
            and mount_summary["summary"]["whole_graph_executions"] == 69
            and mount_summary["summary"][
                "normalized_expansions_byte_identical"
            ]
            == 23
            and mount_summary["summary"]["raw_encoder_bytes_identical"] == 0
            and mount_summary["summary"]["structural_rewrite_uses"] == 329
            and mount_summary["summary"]["max_graph_abs_error"] == 0.0
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
        "integration_not_inflated": mount_summary[
            "A5_production_integrated"
        ]
        is False,
        "validation_v6_unread": mount_summary[
            "validation_v6_accessed"
        ]
        is False,
    }
    if not all(checks.values()):
        raise RuntimeError(
            "A5 Stitch resource audit failed: "
            + canonical(
                {
                    "failed": [
                        name for name, passed in checks.items() if not passed
                    ]
                }
            )
        )
    payload = {
        "version": "FOUNDRY_A5_STITCH_RUNTIME_RESOURCE_AUDIT_V1",
        "status": "A5_STITCH_RUNTIME_RESOURCE_COMPONENT_PASS",
        "limits": limits,
        "meter_selftest": meter_test,
        "mount_receipt": mount,
        "mount_summary": mount_summary,
        "conformance_receipt": conformance,
        "checks": checks,
        "integration": {
            "A5_complete_mount_process_tree_metered": True,
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
        "FOUNDRY_PHASE102_A5_STITCH_RUNTIME_RESOURCE"
        f" status={payload['status']}"
        " mount=PASS conformance=PASS uses=329"
        " integrated=5/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    main()
