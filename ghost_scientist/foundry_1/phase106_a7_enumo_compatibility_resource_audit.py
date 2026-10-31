#!/usr/bin/env python3
"""Meter the fail-closed A7 direct-adapter compatibility audit."""

from __future__ import annotations

import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULT = (
    HERE / "results/phase106_a7_enumo_compatibility_resource_audit.json"
)


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def main() -> None:
    python = pathlib.Path(sys.executable).resolve()
    meter_test = selftest(str(python), ROOT)
    limits = {
        "wall_limit_seconds": 60,
        "cpu_limit_seconds": 45,
        "rss_limit_kib": 4500000,
    }
    receipt = run_metered_tree(
        [
            str(python),
            str(HERE / "phase105_a7_enumo_compatibility_audit.py"),
        ],
        cwd=HERE,
        wall_limit_seconds=limits["wall_limit_seconds"],
        cpu_limit_seconds=limits["cpu_limit_seconds"],
        rss_limit_kib=limits["rss_limit_kib"],
        environment={
            "PYTHONWARNINGS": "ignore",
            "OMP_NUM_THREADS": "1",
            "MKL_NUM_THREADS": "1",
        },
    )
    receipt["expected_status_seen"] = (
        "FOUNDRY_PHASE105_A7_ENUMO_COMPATIBILITY"
        in receipt["stdout_text"]
        and "graphs=23" in receipt["stdout_text"]
        and "direct=0" in receipt["stdout_text"]
        and "unsupported=337" in receipt["stdout_text"]
        and "integrated=6/10" in receipt["stdout_text"]
    )
    audit = json.loads(
        (
            HERE / "results/phase105_a7_enumo_compatibility_audit.json"
        ).read_text()
    )
    checks = {
        "meter_hostile_selftest": meter_test["pass"],
        "natural_termination": (
            receipt["returncode"] == 0
            and receipt["termination"] == "natural"
            and receipt["expected_status_seen"]
        ),
        "cpu_charged": (
            receipt["rusage_user_cpu_ns"]
            + receipt["rusage_system_cpu_ns"]
            > 0
        ),
        "rss_sampled": receipt["peak_group_rss_kib"] > 0,
        "process_group_reaped": receipt["process_group_reaped"],
        "rejected_outcome_preserved": (
            audit["status"] == "A7_DIRECT_ADAPTER_REJECTED"
            and audit["compatibility"]["direct_adapter_possible"] is False
            and audit["framework_surface"]["direct_call_matches"] == 0
            and audit["framework_surface"]["unsupported_calls"] == 337
        ),
        "source_and_metamorphic_boundaries_preserved": (
            audit["source_control"]["full_official_crate_executed"] is False
            and audit["metamorphic_boundary"][
                "entire_rule_set_invariant"
            ]
            is False
        ),
        "integration_not_inflated": (
            audit["integration"]["A7_production_integrated"] is False
            and audit["integration"]["production_integrated_arms"] == 6
        ),
        "P3_incomplete": audit["P3"]["complete"] is False,
        "validation_v6_unread": audit["validation_v6_accessed"] is False,
        "prospective_unauthorized": audit[
            "prospective_trial_authorized"
        ]
        is False,
    }
    if not all(checks.values()):
        raise RuntimeError(
            "A7 compatibility resource audit failed: "
            + canonical(
                {
                    "failed": [
                        name for name, passed in checks.items() if not passed
                    ]
                }
            )
        )
    payload = {
        "version": "FOUNDRY_A7_ENUMO_COMPATIBILITY_RESOURCE_AUDIT_V1",
        "status": "A7_COMPATIBILITY_RESOURCE_PASS",
        "limits": limits,
        "meter_selftest": meter_test,
        "receipt": receipt,
        "checks": checks,
        "integration": {
            "A7_compatibility_outcome_metered": True,
            "A7_production_integrated": False,
            "production_integrated_arms": 6,
            "required_arms": 10,
        },
        "P3": {"complete": False},
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE106_A7_ENUMO_COMPATIBILITY_RESOURCE"
        f" status={payload['status']}"
        " direct=REJECTED meter=PASS integrated=6/10"
        " P3=false prospective=false"
    )


if __name__ == "__main__":
    main()
