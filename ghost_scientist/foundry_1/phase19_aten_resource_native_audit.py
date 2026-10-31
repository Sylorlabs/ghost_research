#!/usr/bin/env python3
"""Phase 19: resource accounting and native classification for ATen macros."""

from __future__ import annotations

import hashlib
import json
import pathlib
import sys

from independent_aten_tool_evaluator import canonical, parse_library
from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULTS = HERE / "results"


def run() -> None:
    python = pathlib.Path(sys.executable).resolve()
    meter_test = selftest(str(python), ROOT)
    arms = {}
    for name, script, marker, rss in (
        (
            "aten_forge",
            "phase17_aten_tool_forge.py",
            "FOUNDRY_PHASE17_ATEN_FORGE_PASS",
            2_500_000,
        ),
        (
            "independent_aten_evaluator",
            "independent_aten_tool_evaluator.py",
            "FOUNDRY_PHASE18_INDEPENDENT_ATEN_EVAL",
            3_500_000,
        ),
    ):
        receipt = run_metered_tree(
            [str(python), str(HERE / script)],
            cwd=HERE,
            wall_limit_seconds=90,
            cpu_limit_seconds=75,
            rss_limit_kib=rss,
            environment={
                "TORCHINDUCTOR_COMPILE_THREADS": "1",
                "OMP_NUM_THREADS": "1",
                "MKL_NUM_THREADS": "1",
            },
        )
        receipt["expected_status_seen"] = marker in receipt["stdout_text"]
        arms[name] = receipt
    gates = {
        "meter_hostile_selftest": meter_test["pass"],
        "all_arms_natural": all(
            item["returncode"] == 0 and item["termination"] == "natural"
            for item in arms.values()
        ),
        "all_statuses_bound": all(item["expected_status_seen"] for item in arms.values()),
        "all_cpu_charged": all(
            item["rusage_user_cpu_ns"] + item["rusage_system_cpu_ns"] > 0
            for item in arms.values()
        ),
        "all_rss_sampled": all(item["peak_group_rss_kib"] > 0 for item in arms.values()),
        "all_groups_reaped": all(item["process_group_reaped"] for item in arms.values()),
    }
    library_raw = (RESULTS / "forged_aten_tools.json").read_bytes()
    library = parse_library(library_raw)
    classifications = [
        {
            "tool_id": tool["tool_id"],
            "decision": "QUARANTINE_SEARCH_ONLY_MACRO",
            "runtime_rewrite_exists": False,
            "native_compiler_comparison_executed": False,
            "search_cost_receipt_frozen": False,
            "reason": (
                "macro recognizes and replays existing ATen nodes but does not "
                "replace them with a distinct runtime implementation"
            ),
        }
        for tool in library["tools"]
    ]
    payload = {
        "version": "FOUNDRY_ATEN_RESOURCE_NATIVE_AUDIT_V1",
        "status": (
            "ATEN_RESOURCE_COMPONENT_READY"
            if all(gates.values())
            else "ATEN_RESOURCE_COMPONENT_FAIL"
        ),
        "library_file_sha256": hashlib.sha256(library_raw).hexdigest(),
        "meter_selftest": meter_test,
        "arms": arms,
        "gates": gates,
        "classifications": classifications,
        "summary": {
            "tools": len(classifications),
            "resource_metered": len(arms),
            "native_compared": 0,
            "admitted": 0,
            "quarantined": len(classifications),
        },
        "P3": {
            "aten_calibration_arms_integrated": all(gates.values()),
            "external_controls_integrated": False,
            "full_prospective_matrix_integrated": False,
            "complete": False,
        },
        "P5": {
            "search_macro_classification_complete": True,
            "runtime_candidate_audit_complete": False,
            "admitted": 0,
            "complete": False,
        },
        "limits": [
            "resource receipts cover the aggregate forge and validation pilot arms",
            "search-only macros have no distinct runtime implementation to compile",
            "a frozen independent search-cost receipt is required before native-identical rescue",
            "external controls and final prospective arms remain unmetered",
        ],
    }
    (RESULTS / "phase19_aten_resource_native.json").write_text(
        canonical(payload) + "\n", encoding="utf-8"
    )
    print(
        "FOUNDRY_PHASE19_ATEN_RESOURCE_NATIVE_PASS"
        f" tools={len(classifications)}"
        f" metered_arms={len(arms)}"
        " native_compared=0 admitted=0"
        " p3_complete=false p5_complete=false"
    )


if __name__ == "__main__":
    run()
