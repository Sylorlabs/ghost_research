#!/usr/bin/env python3
"""Meter the Babble source build and conformance execution as one process tree."""

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
        [str(python), str(HERE / "phase41_babble_source_control.py")],
        cwd=HERE,
        wall_limit_seconds=90,
        cpu_limit_seconds=60,
        rss_limit_kib=1_500_000,
        environment={
            "HOME": str(pathlib.Path.home()),
            "CARGO_HOME": "/tmp/foundry-babble-cargo",
            "RUSTUP_HOME": str(pathlib.Path.home() / ".rustup"),
            "PATH": f"{pathlib.Path.home() / '.cargo/bin'}:/usr/bin:/bin",
        },
    )
    result = json.loads(
        (RESULTS / "phase41_babble_source_control.json").read_text(
            encoding="utf-8"
        )
    )
    receipt_ok = (
        receipt["returncode"] == 0
        and receipt["termination"] == "natural"
        and receipt["process_group_reaped"]
        and receipt["observed_process_count"] >= 4
        and "FOUNDRY_PHASE41_BABBLE_SOURCE" in receipt["stdout_text"]
    )
    conformance = (
        result["status"] == "BABBLE_SOURCE_CONTROL_STRUCTURAL_PASS"
        and result["source_records_exact"]
        and result["upstream_algorithm_source_executed"]
        and result["structural_conformance_passed"]
    )
    passed = meter_test["pass"] and receipt_ok and conformance
    payload = {
        "version": "FOUNDRY_BABBLE_SOURCE_RESOURCE_AUDIT_V1",
        "status": (
            "BABBLE_SOURCE_CONTROL_RESOURCE_PASS"
            if passed
            else "BABBLE_SOURCE_CONTROL_RESOURCE_FAIL"
        ),
        "meter_selftest": meter_test,
        "receipt": receipt,
        "receipt_complete": receipt_ok,
        "source_structural_conformance_passed": conformance,
        "published_numeric_claim_exact": result["published_claim_audit"][
            "numeric_claim_exact"
        ],
        "P1": {
            "source_faithful_controls_reproduced": 2 if conformance else 1,
            "official_binary_controls_reproduced": 0,
            "controls_required": 4,
            "complete": False,
        },
        "P3": {
            "metered_source_control_arms": 2 if receipt_ok else 1,
            "controls_required": 4,
            "complete": False,
        },
    }
    (RESULTS / "phase42_babble_source_resource_audit.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE42_BABBLE_RESOURCE"
        f" status={payload['status']}"
        f" controls={payload['P1']['source_faithful_controls_reproduced']}/4"
        f" processes={receipt['observed_process_count']}"
    )


if __name__ == "__main__":
    run()
