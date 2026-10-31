#!/usr/bin/env python3
"""Meter A5 shared-resource assembly and falsification conformance."""

from __future__ import annotations

import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULT = (
    HERE
    / "results/phase104_a5_shared_resource_batch_resource_audit.json"
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
            str(HERE / "a5_shared_resource_batch.py"),
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
            str(HERE / "phase103_a5_shared_resource_batch_conformance.py"),
        ],
        cwd=HERE,
        wall_limit_seconds=limits["wall_limit_seconds"],
        cpu_limit_seconds=limits["cpu_limit_seconds"],
        rss_limit_kib=limits["rss_limit_kib"],
    )
    assembly_summary = json.loads(assembly["stdout_text"])
    conformance["expected_status_seen"] = (
        "FOUNDRY_PHASE103_A5_SHARED_RESOURCE_BATCH"
        in conformance["stdout_text"]
        and "base_pairs=23/23" in conformance["stdout_text"]
        and "uses=329" in conformance["stdout_text"]
        and "hostile=19/19" in conformance["stdout_text"]
        and "integrated=6/10" in conformance["stdout_text"]
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
        "assembly_summary_exact": (
            assembly_summary["artifact_outputs"] == 23
            and assembly_summary["aggregate_accounting"][
                "unique_resource_receipts_charged"
            ]
            == 1
            and assembly_summary["aggregate_accounting"][
                "direct_structural_uses"
            ]
            == 329
            and assembly_summary["aggregate_accounting"][
                "candidate_generation_charged_artifacts"
            ]
            == 1
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
        "integration_exactly_6_of_10": (
            assembly_summary["production_integration_classification"]
            == "PRODUCTION_INTEGRATED_CALIBRATION_STRUCTURAL_CONTROL"
        ),
        "P3_incomplete": assembly_summary["P3_complete"] is False,
        "validation_v6_unread": assembly_summary[
            "validation_v6_accessed"
        ]
        is False,
    }
    if not all(checks.values()):
        raise RuntimeError(
            "A5 shared batch resource audit failed: "
            + canonical(
                {
                    "failed": [
                        name for name, passed in checks.items() if not passed
                    ]
                }
            )
        )
    payload = {
        "version": "FOUNDRY_A5_SHARED_RESOURCE_BATCH_RESOURCE_AUDIT_V1",
        "status": "A5_SHARED_RESOURCE_BATCH_RESOURCE_PASS",
        "limits": limits,
        "meter_selftest": meter_test,
        "assembly_receipt": assembly,
        "conformance_receipt": conformance,
        "checks": checks,
        "integration": {
            "A5_complete_contract_batch_metered": True,
            "A5_production_integrated": True,
            "production_integrated_arms": 6,
            "required_arms": 10,
        },
        "P3": {"complete": False},
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE104_A5_SHARED_RESOURCE_BATCH_RESOURCE"
        f" status={payload['status']}"
        " assembly=PASS conformance=PASS hostile=19/19"
        " integrated=6/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    main()
