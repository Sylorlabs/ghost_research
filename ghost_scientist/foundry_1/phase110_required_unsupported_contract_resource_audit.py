#!/usr/bin/env python3
"""Meter required-unsupported batch assembly and hostile conformance."""

from __future__ import annotations

import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULT = (
    HERE
    / "results/phase110_required_unsupported_contract_resource_audit.json"
)


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def main() -> None:
    python = pathlib.Path(sys.executable).resolve()
    meter_test = selftest(str(python), ROOT)
    limits = {
        "wall_limit_seconds": 30,
        "cpu_limit_seconds": 20,
        "rss_limit_kib": 1000000,
    }
    assembly = run_metered_tree(
        [
            str(python),
            str(HERE / "required_unsupported_contract_batch.py"),
            "--summary-only",
        ],
        cwd=HERE,
        wall_limit_seconds=limits["wall_limit_seconds"],
        cpu_limit_seconds=limits["cpu_limit_seconds"],
        rss_limit_kib=limits["rss_limit_kib"],
    )
    conformance = run_metered_tree(
        [
            str(python),
            str(
                HERE
                / "phase109_required_unsupported_contract_conformance.py"
            ),
        ],
        cwd=HERE,
        wall_limit_seconds=limits["wall_limit_seconds"],
        cpu_limit_seconds=limits["cpu_limit_seconds"],
        rss_limit_kib=limits["rss_limit_kib"],
    )
    summary = json.loads(assembly["stdout_text"])
    conformance["expected_status_seen"] = (
        "FOUNDRY_PHASE109_REQUIRED_UNSUPPORTED_CONTRACT"
        in conformance["stdout_text"]
        and "pairs=92/92" in conformance["stdout_text"]
        and "CPU=EXACT" in conformance["stdout_text"]
        and "hostile=25/25" in conformance["stdout_text"]
        and "P3=true" in conformance["stdout_text"]
    )
    receipts = [assembly, conformance]
    checks = {
        "meter_hostile_selftest": meter_test["pass"],
        "assembly_natural": (
            assembly["returncode"] == 0
            and assembly["termination"] == "natural"
        ),
        "conformance_natural": (
            conformance["returncode"] == 0
            and conformance["termination"] == "natural"
            and conformance["expected_status_seen"]
        ),
        "summary_exact": (
            summary["artifact_outputs"] == 92
            and summary["aggregate_accounting"][
                "required_unsupported_outputs"
            ]
            == 92
            and summary["aggregate_accounting"][
                "unique_resource_receipts_charged"
            ]
            == 1
            and summary["aggregate_accounting"][
                "measured_process_cpu_ns"
            ]
            == summary["aggregate_accounting"]["allocated_ledger_cpu_ns"]
            and summary["aggregate_accounting"]["cpu_charged_bindings"] == 4
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
        "no_integration_inflation": (
            summary["outcome_classification"][
                "newly_production_integrated_arms"
            ]
            == 0
            and summary["outcome_classification"][
                "production_integrated_arms"
            ]
            == 6
        ),
        "P3_complete": summary["P3_complete_resource_meter"] is True,
        "validation_v6_unread": summary["validation_v6_accessed"] is False,
    }
    if not all(checks.values()):
        raise RuntimeError(
            "required-unsupported contract resource audit failed: "
            + canonical(
                {
                    "failed": [
                        name for name, passed in checks.items() if not passed
                    ]
                }
            )
        )
    payload = {
        "version": (
            "FOUNDRY_REQUIRED_UNSUPPORTED_CONTRACT_RESOURCE_AUDIT_V1"
        ),
        "status": "REQUIRED_UNSUPPORTED_CONTRACT_RESOURCE_PASS",
        "limits": limits,
        "meter_selftest": meter_test,
        "assembly_receipt": assembly,
        "conformance_receipt": conformance,
        "checks": checks,
        "integration": {
            "unsupported_batch_and_hostile_gate_metered": True,
            "newly_production_integrated_arms": 0,
            "production_integrated_arms": 6,
            "required_arms": 10,
        },
        "P3": {
            "complete_resource_meter": True,
            "complete": True,
        },
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE110_REQUIRED_UNSUPPORTED_CONTRACT_RESOURCE"
        f" status={payload['status']}"
        " assembly=PASS conformance=PASS hostile=25/25"
        " integrated=6/10 P3=true prospective=false"
    )


if __name__ == "__main__":
    main()
