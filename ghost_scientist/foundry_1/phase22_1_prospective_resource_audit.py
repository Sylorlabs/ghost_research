#!/usr/bin/env python3
"""Outcome-blind meter-API remediation for the unchanged frozen v2 trial."""

from __future__ import annotations

import json
import pathlib
import sys

from freeze_aten_prospective_v2 import verify as verify_v2
from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def run() -> None:
    verify_v2()
    python = pathlib.Path(sys.executable).resolve()
    receipt = run_metered_tree(
        [str(python), str(HERE / "phase21_prospective_aten_trial.py")],
        cwd=HERE,
        wall_limit_seconds=120,
        cpu_limit_seconds=100,
        rss_limit_kib=4_000_000,
        environment={
            "TORCHINDUCTOR_COMPILE_THREADS": "1",
            "OMP_NUM_THREADS": "1",
            "MKL_NUM_THREADS": "1",
        },
    )
    expected = "FOUNDRY_PHASE21_ATEN_PROSPECTIVE"
    gates = {
        "natural_exit": receipt["termination"] == "natural",
        "returncode_zero": receipt["returncode"] == 0,
        "process_group_reaped": receipt["process_group_reaped"],
        "status_bound": expected in receipt["stdout_text"],
        "rss_sampled": receipt["peak_group_rss_kib"] > 0,
        "cpu_charged": (
            receipt["rusage_user_cpu_ns"] + receipt["rusage_system_cpu_ns"] > 0
        ),
    }
    passed = all(gates.values())
    payload = {
        "version": "FOUNDRY_ATEN_PROSPECTIVE_RESOURCE_AUDIT_V2_1",
        "status": (
            "PROSPECTIVE_RESOURCE_PASS"
            if passed
            else "PROSPECTIVE_RESOURCE_FAIL"
        ),
        "remediation": "METER_API_ONLY",
        "candidate_outcomes_observed_before_remediation": False,
        "receipt": receipt,
        "gates": gates,
        "P3_component_metered": passed,
        "P3_complete": False,
    }
    (RESULTS / "phase22_1_prospective_resource_audit.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE22_1_PROSPECTIVE_RESOURCE"
        f" status={payload['status']}"
        f" peak_rss_kib={receipt['peak_group_rss_kib']}"
        f" wall_ns={receipt['wall_ns']}"
    )


if __name__ == "__main__":
    run()
