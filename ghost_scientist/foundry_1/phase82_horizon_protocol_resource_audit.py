#!/usr/bin/env python3
"""Meter the unit-rejection and two-axis clarification audits."""

from __future__ import annotations

import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULT = HERE / "results/phase82_horizon_protocol_resource_audit.json"


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
    commands = {
        "unit_mapping": (
            "phase80_horizon_unit_mapping_audit.py",
            "FOUNDRY_PHASE80_HORIZON_UNIT_MAPPING",
        ),
        "clarification_conformance": (
            "phase81_horizon_clarification_conformance.py",
            "FOUNDRY_PHASE81_HORIZON_CLARIFICATION",
        ),
    }
    receipts = {}
    for name, (script, marker) in commands.items():
        receipt = run_metered_tree(
            [str(python), str(HERE / script)],
            cwd=HERE,
            wall_limit_seconds=limits["wall_limit_seconds"],
            cpu_limit_seconds=limits["cpu_limit_seconds"],
            rss_limit_kib=limits["rss_limit_kib"],
            environment={"PYTHONWARNINGS": "ignore"},
        )
        receipt["expected_status_seen"] = marker in receipt["stdout_text"]
        receipts[name] = receipt
    checks = {
        "meter_hostile_selftest": meter_test["pass"],
        "identical_declared_ceilings": True,
        "both_natural": all(
            row["returncode"] == 0 and row["termination"] == "natural"
            for row in receipts.values()
        ),
        "both_statuses_bound": all(
            row["expected_status_seen"] for row in receipts.values()
        ),
        "both_cpu_charged": all(
            row["rusage_user_cpu_ns"] + row["rusage_system_cpu_ns"] > 0
            for row in receipts.values()
        ),
        "both_rss_sampled": all(
            row["peak_group_rss_kib"] > 0 for row in receipts.values()
        ),
        "both_groups_reaped": all(
            row["process_group_reaped"] for row in receipts.values()
        ),
    }
    if not all(checks.values()):
        raise RuntimeError("horizon protocol resource audit failed")
    payload = {
        "version": "FOUNDRY_HORIZON_PROTOCOL_RESOURCE_AUDIT_V1",
        "status": "HORIZON_PROTOCOL_RESOURCE_PASS",
        "limits": limits,
        "meter_selftest": meter_test,
        "receipts": receipts,
        "checks": checks,
        "P3": {
            "horizon_unit_audit_metered": True,
            "horizon_clarification_audit_metered": True,
            "all_required_prospective_arms_metered": False,
            "complete": False,
        },
        "validation_v6_source_runtime_graph_or_outcome_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE82_HORIZON_PROTOCOL_RESOURCE"
        f" status={payload['status']}"
        f" receipts={len(receipts)}/2"
        " P3=false prospective=false"
    )


if __name__ == "__main__":
    run()
