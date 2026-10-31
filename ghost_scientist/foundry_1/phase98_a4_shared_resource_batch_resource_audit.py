#!/usr/bin/env python3
"""Meter A4 shared batch assembly and hostile conformance."""

from __future__ import annotations

import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULT = (
    HERE / "results/phase98_a4_shared_resource_batch_resource_audit.json"
)


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def main() -> None:
    python = pathlib.Path(sys.executable).resolve()
    meter_test = selftest(str(python), ROOT)
    limits = {
        "wall_limit_seconds": 20,
        "cpu_limit_seconds": 15,
        "rss_limit_kib": 524288,
    }
    environment = {"PYTHONWARNINGS": "ignore"}
    batch = run_metered_tree(
        [
            str(python),
            str(HERE / "a4_shared_resource_batch.py"),
            "--summary-only",
        ],
        cwd=HERE,
        wall_limit_seconds=limits["wall_limit_seconds"],
        cpu_limit_seconds=limits["cpu_limit_seconds"],
        rss_limit_kib=limits["rss_limit_kib"],
        environment=environment,
    )
    summary = json.loads(batch["stdout_text"])
    conformance = run_metered_tree(
        [
            str(python),
            str(HERE / "phase97_a4_shared_resource_batch_conformance.py"),
        ],
        cwd=HERE,
        wall_limit_seconds=limits["wall_limit_seconds"],
        cpu_limit_seconds=limits["cpu_limit_seconds"],
        rss_limit_kib=limits["rss_limit_kib"],
        environment=environment,
    )
    conformance["expected_status_seen"] = (
        "FOUNDRY_PHASE97_A4_SHARED_RESOURCE_BATCH"
        in conformance["stdout_text"]
        and "base_pairs=23/23" in conformance["stdout_text"]
        and "hostile=11/11" in conformance["stdout_text"]
        and "integrated=5/10" in conformance["stdout_text"]
    )
    receipts = [batch, conformance]
    checks = {
        "meter_hostile_selftest": meter_test["pass"],
        "identical_declared_ceilings": True,
        "batch_natural": batch["returncode"] == 0
        and batch["termination"] == "natural",
        "conformance_natural": (
            conformance["returncode"] == 0
            and conformance["termination"] == "natural"
            and conformance["expected_status_seen"]
        ),
        "summary_exact": (
            summary["artifact_outputs"] == 23
            and summary["base_contract_primary_accepts"] == 23
            and summary["base_contract_independent_accepts"] == 23
            and summary["aggregate_accounting"][
                "unique_resource_receipts_charged"
            ]
            == 1
            and summary["aggregate_accounting"][
                "resource_multiplier_applied"
            ]
            == 1
            and summary["production_integration_classification"]
            == "PRODUCTION_INTEGRATED_CALIBRATION_ARM"
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
        "validation_v6_unread": summary["validation_v6_accessed"] is False,
    }
    if not all(checks.values()):
        raise RuntimeError("A4 shared batch resource audit failed")
    payload = {
        "version": "FOUNDRY_A4_SHARED_RESOURCE_BATCH_RESOURCE_AUDIT_V1",
        "status": "A4_SHARED_RESOURCE_BATCH_RESOURCE_PASS",
        "limits": limits,
        "meter_selftest": meter_test,
        "batch_receipt": batch,
        "batch_summary": summary,
        "conformance_receipt": conformance,
        "checks": checks,
        "integration": {
            "A4_batch_assembly_process_tree_metered": True,
            "production_integrated_arms": 5,
            "required_arms": 10,
        },
        "P3": {"complete": False},
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE98_A4_SHARED_RESOURCE_BATCH_RESOURCE"
        f" status={payload['status']}"
        " batch=PASS hostile=11/11 integrated=5/10"
        " P3=false prospective=false"
    )


if __name__ == "__main__":
    main()
