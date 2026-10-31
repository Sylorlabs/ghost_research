#!/usr/bin/env python3
"""Meter local trace authentication and dual-parser replay process trees."""

from __future__ import annotations

import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULT = HERE / "results/phase79_offline_trace_resource_audit.json"


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
        "local_provenance": (
            "phase77_local_trace_provenance.py",
            "FOUNDRY_PHASE77_LOCAL_TRACE_PROVENANCE",
        ),
        "offline_replay": (
            "phase78_offline_trace_replay.py",
            "FOUNDRY_PHASE78_OFFLINE_TRACE_REPLAY",
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
        raise RuntimeError("offline trace resource audit failed")
    payload = {
        "version": "FOUNDRY_OFFLINE_TRACE_RESOURCE_AUDIT_V1",
        "status": "OFFLINE_TRACE_PIPELINE_RESOURCE_PASS",
        "limits": limits,
        "meter_selftest": meter_test,
        "receipts": receipts,
        "checks": checks,
        "P3": {
            "trace_provenance_process_tree_metered": True,
            "offline_replay_process_tree_metered": True,
            "all_required_prospective_arms_metered": False,
            "complete": False,
        },
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE79_OFFLINE_TRACE_RESOURCE"
        f" status={payload['status']}"
        f" receipts={len(receipts)}/2"
        " P3=false prospective=false"
    )


if __name__ == "__main__":
    run()
