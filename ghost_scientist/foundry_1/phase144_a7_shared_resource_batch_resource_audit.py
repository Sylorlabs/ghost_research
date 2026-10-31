#!/usr/bin/env python3
"""Meter A7 shared-resource assembly and falsification conformance."""

from __future__ import annotations

import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULT = HERE / "results/phase144_a7_shared_resource_batch_resource_audit.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def main() -> None:
    python = pathlib.Path(sys.executable).resolve()
    meter_test = selftest(str(python), ROOT)
    limits = {
        "wall_limit_seconds": 30,
        "cpu_limit_seconds": 20,
        "rss_limit_kib": 1_000_000,
    }
    assembly = run_metered_tree(
        [
            str(python),
            str(HERE / "a7_shared_resource_batch.py"),
            "--summary-only",
        ],
        cwd=HERE,
        **limits,
    )
    conformance = run_metered_tree(
        [
            str(python),
            str(HERE / "phase143_a7_shared_resource_batch_conformance.py"),
        ],
        cwd=HERE,
        **limits,
    )
    assembly_summary = json.loads(assembly["stdout_text"])
    conformance["expected_status_seen"] = (
        "FOUNDRY_PHASE143_A7_SHARED_RESOURCE_BATCH"
        in conformance["stdout_text"]
        and "base_pairs=23/23" in conformance["stdout_text"]
        and "raw_uses=24" in conformance["stdout_text"]
        and "unique=12" in conformance["stdout_text"]
        and "hostile=22/22" in conformance["stdout_text"]
        and "integrated=7/10" in conformance["stdout_text"]
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
                "raw_selected_rule_uses"
            ]
            == 24
            and assembly_summary["aggregate_accounting"][
                "unique_selected_transformations"
            ]
            == 12
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
        "integration_exactly_7_of_10": (
            assembly_summary["production_integration_classification"]
            == "PRODUCTION_INTEGRATED_ADAPTED_CALIBRATION_RULE_CONTROL"
        ),
        "P3_incomplete": assembly_summary["P3_complete"] is False,
        "validation_v6_unread": assembly_summary[
            "validation_v6_accessed"
        ]
        is False,
    }
    if not all(checks.values()):
        raise RuntimeError(
            "A7 shared batch resource audit failed: "
            + canonical({"failed": [key for key, value in checks.items() if not value]})
        )
    payload = {
        "version": "FOUNDRY_A7_SHARED_RESOURCE_BATCH_RESOURCE_AUDIT_V1",
        "status": "A7_SHARED_RESOURCE_BATCH_RESOURCE_PASS",
        "limits": limits,
        "meter_selftest": meter_test,
        "assembly_receipt": assembly,
        "conformance_receipt": conformance,
        "checks": checks,
        "integration": {
            "A7_complete_contract_batch_metered": True,
            "A7_production_integrated": True,
            "production_integrated_arms": 7,
            "required_arms": 10,
        },
        "P3": {"complete": False},
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE144_A7_SHARED_RESOURCE_BATCH_RESOURCE"
        " status=A7_SHARED_RESOURCE_BATCH_RESOURCE_PASS"
        " assembly=PASS conformance=PASS hostile=22/22"
        " integrated=7/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    main()
