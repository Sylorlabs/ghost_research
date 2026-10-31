#!/usr/bin/env python3
"""Meter the frozen ATen prospective component without modifying it."""

from __future__ import annotations

import json
import pathlib
import sys

from resource_meter_v2 import Limits, meter


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def run() -> None:
    limits = Limits(wall_seconds=120, cpu_seconds=100, rss_kib=4_000_000)
    receipt = meter(
        [sys.executable, "phase21_prospective_aten_trial.py"],
        HERE,
        limits,
    )
    expected = "FOUNDRY_PHASE21_ATEN_PROSPECTIVE"
    pass_receipt = (
        receipt["returncode"] == 0
        and receipt["termination"] == "natural"
        and receipt["process_group_reaped"]
        and expected in receipt["stdout_text"]
    )
    payload = {
        "version": "FOUNDRY_ATEN_PROSPECTIVE_RESOURCE_AUDIT_V2",
        "status": (
            "PROSPECTIVE_RESOURCE_PASS"
            if pass_receipt
            else "PROSPECTIVE_RESOURCE_FAIL"
        ),
        "receipt": receipt,
        "gates": {
            "natural_exit": receipt["termination"] == "natural",
            "returncode_zero": receipt["returncode"] == 0,
            "process_group_reaped": receipt["process_group_reaped"],
            "status_bound": expected in receipt["stdout_text"],
        },
        "P3_component_metered": pass_receipt,
        "P3_complete": False,
    }
    (RESULTS / "phase22_prospective_resource_audit.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE22_PROSPECTIVE_RESOURCE"
        f" status={payload['status']}"
        f" peak_rss_kib={receipt['peak_group_rss_kib']}"
        f" wall_ns={receipt['wall_ns']}"
    )


if __name__ == "__main__":
    run()
