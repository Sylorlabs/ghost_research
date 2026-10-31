#!/usr/bin/env python3
"""Meter arm-contract conformance including both strict verifiers."""

from __future__ import annotations

import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULT = HERE / "results/phase84_arm_adapter_contract_resource_audit.json"


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
    receipt = run_metered_tree(
        [
            str(python),
            str(HERE / "phase83_arm_adapter_contract_conformance.py"),
        ],
        cwd=HERE,
        wall_limit_seconds=limits["wall_limit_seconds"],
        cpu_limit_seconds=limits["cpu_limit_seconds"],
        rss_limit_kib=limits["rss_limit_kib"],
        environment={"PYTHONWARNINGS": "ignore"},
    )
    receipt["expected_status_seen"] = (
        "FOUNDRY_PHASE83_ARM_ADAPTER_CONFORMANCE"
        in receipt["stdout_text"]
        and "hostile=9/9" in receipt["stdout_text"]
        and "integrated=2/10" in receipt["stdout_text"]
    )
    checks = {
        "meter_hostile_selftest": meter_test["pass"],
        "natural_termination": (
            receipt["returncode"] == 0
            and receipt["termination"] == "natural"
        ),
        "status_bound": receipt["expected_status_seen"],
        "cpu_charged": (
            receipt["rusage_user_cpu_ns"]
            + receipt["rusage_system_cpu_ns"]
            > 0
        ),
        "rss_sampled": receipt["peak_group_rss_kib"] > 0,
        "group_reaped": receipt["process_group_reaped"],
    }
    if not all(checks.values()):
        raise RuntimeError("arm adapter contract resource audit failed")
    payload = {
        "version": "FOUNDRY_ARM_ADAPTER_RESOURCE_AUDIT_V1",
        "status": "ARM_ADAPTER_CONTRACT_RESOURCE_PASS",
        "limits": limits,
        "meter_selftest": meter_test,
        "receipt": receipt,
        "checks": checks,
        "P3": {
            "adapter_contract_conformance_metered": True,
            "all_required_adapter_implementations_metered": False,
            "all_required_prospective_arms_metered": False,
            "complete": False,
        },
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE84_ARM_ADAPTER_RESOURCE"
        f" status={payload['status']}"
        " integrated=2/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    run()
