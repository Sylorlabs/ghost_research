#!/usr/bin/env python3
"""Meter Enumo source conformance as one complete process tree."""

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
    receipt = run_metered_tree(
        [str(python), str(HERE / "phase45_enumo_source_control.py")],
        cwd=HERE,
        wall_limit_seconds=150,
        cpu_limit_seconds=120,
        rss_limit_kib=2_000_000,
        environment={
            "HOME": str(pathlib.Path.home()),
            "CARGO_HOME": "/tmp/foundry-enumo-cargo",
            "RUSTUP_HOME": str(pathlib.Path.home() / ".rustup"),
            "PATH": f"{pathlib.Path.home() / '.cargo/bin'}:/usr/bin:/bin",
        },
    )
    result = json.loads(
        (RESULTS / "phase45_enumo_source_control.json").read_text(
            encoding="utf-8"
        )
    )
    receipt_ok = (
        receipt["returncode"] == 0
        and receipt["termination"] == "natural"
        and receipt["process_group_reaped"]
        and receipt["observed_process_count"] >= 6
        and "FOUNDRY_PHASE45_ENUMO_SOURCE" in receipt["stdout_text"]
    )
    conformance = (
        result["status"] == "ENUMO_SOURCE_CONTROL_CONFORMANCE_PASS"
        and result["source_records_exact"]
        and result["upstream_algorithm_source_executed"]
        and result["official_boolean_test_logic_executed"]
        and result["conformance_passed"]
    )
    passed = meter_test["pass"] and receipt_ok and conformance
    payload = {
        "version": "FOUNDRY_ENUMO_SOURCE_RESOURCE_AUDIT_V1",
        "status": (
            "ENUMO_SOURCE_CONTROL_RESOURCE_PASS"
            if passed
            else "ENUMO_SOURCE_CONTROL_RESOURCE_FAIL"
        ),
        "meter_selftest": meter_test,
        "receipt": receipt,
        "receipt_complete": receipt_ok,
        "source_conformance_passed": conformance,
        "P1": {
            "source_faithful_controls_reproduced": 3 if conformance else 2,
            "official_binary_controls_reproduced": 0,
            "controls_required": 4,
            "complete": False,
        },
        "P3": {
            "metered_source_control_arms": 3 if receipt_ok else 2,
            "controls_required": 4,
            "complete": False,
        },
    }
    (RESULTS / "phase46_enumo_source_resource_audit.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE46_ENUMO_RESOURCE"
        f" status={payload['status']}"
        f" controls={payload['P1']['source_faithful_controls_reproduced']}/4"
        f" processes={receipt['observed_process_count']}"
    )


if __name__ == "__main__":
    run()
