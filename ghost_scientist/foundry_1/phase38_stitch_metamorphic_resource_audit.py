#!/usr/bin/env python3
"""Meter the pre-frozen Stitch metamorphic control."""

from __future__ import annotations

import json
import pathlib
import sys

from freeze_stitch_metamorphic_v1 import verify as verify_prefreeze
from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULTS = HERE / "results"


def run() -> None:
    freeze = verify_prefreeze()
    python = pathlib.Path(sys.executable).resolve()
    meter_test = selftest(str(python), ROOT)
    receipt = run_metered_tree(
        [str(python), str(HERE / "phase37_stitch_metamorphic_control.py")],
        cwd=HERE,
        wall_limit_seconds=60,
        cpu_limit_seconds=45,
        rss_limit_kib=1_000_000,
        environment={
            "HOME": str(pathlib.Path.home()),
            "CARGO_HOME": "/tmp/foundry-stitch-cargo-home",
            "RUSTUP_HOME": str(pathlib.Path.home() / ".rustup"),
            "PATH": f"{pathlib.Path.home() / '.cargo/bin'}:/usr/bin:/bin",
        },
    )
    result = json.loads(
        (RESULTS / "phase37_stitch_metamorphic_control.json").read_text(
            encoding="utf-8"
        )
    )
    receipt_ok = (
        receipt["returncode"] == 0
        and receipt["termination"] == "natural"
        and receipt["process_group_reaped"]
        and receipt["observed_process_count"] >= 2
        and "FOUNDRY_PHASE37_STITCH_METAMORPHIC" in receipt["stdout_text"]
    )
    passed = (
        meter_test["pass"]
        and receipt_ok
        and result["status"] == "STITCH_METAMORPHIC_CONTROL_PASS"
        and result["metamorphic_relation_passed"]
    )
    payload = {
        "version": "FOUNDRY_STITCH_METAMORPHIC_RESOURCE_AUDIT_V1",
        "status": (
            "STITCH_METAMORPHIC_RESOURCE_PASS"
            if passed
            else "STITCH_METAMORPHIC_RESOURCE_FAIL"
        ),
        "prefreeze_records_sha256": freeze["records_sha256"],
        "meter_selftest": meter_test,
        "receipt": receipt,
        "receipt_complete": receipt_ok,
        "metamorphic_relation_passed": result[
            "metamorphic_relation_passed"
        ],
        "P3": {
            "metamorphic_control_arm_integrated": receipt_ok,
            "complete": False,
        },
    }
    (RESULTS / "phase38_stitch_metamorphic_resource_audit.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE38_STITCH_METAMORPHIC_RESOURCE"
        f" status={payload['status']}"
        f" relation_passed={str(payload['metamorphic_relation_passed']).lower()}"
    )


if __name__ == "__main__":
    run()
