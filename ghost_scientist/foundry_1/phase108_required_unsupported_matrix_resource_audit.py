#!/usr/bin/env python3
"""Meter the authenticated required-unsupported matrix audit."""

from __future__ import annotations

import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULT = (
    HERE
    / "results/phase108_required_unsupported_matrix_resource_audit.json"
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
            str(HERE / "phase107_required_unsupported_matrix_audit.py"),
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
        "FOUNDRY_PHASE107_REQUIRED_UNSUPPORTED_MATRIX"
        in receipt["stdout_text"]
        and "arms=4" in receipt["stdout_text"]
        and "outcomes=92" in receipt["stdout_text"]
        and "integrated=6/10" in receipt["stdout_text"]
    )
    audit = json.loads(
        (
            HERE / "results/phase107_required_unsupported_matrix_audit.json"
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
        "complete_matrix_preserved": (
            audit["status"]
            == "REQUIRED_UNSUPPORTED_MATRIX_COMPONENT_PASS"
            and len(audit["outcomes"]) == 92
            and audit["integration"][
                "explicit_required_unsupported_arms"
            ]
            == 4
        ),
        "integration_not_inflated": (
            audit["integration"]["newly_production_integrated_arms"] == 0
            and audit["integration"]["production_integrated_arms"] == 6
        ),
        "P3_not_premature": audit["P3"]["complete"] is False,
        "validation_v6_unread": audit["validation_v6_accessed"] is False,
        "prospective_unauthorized": audit[
            "prospective_trial_authorized"
        ]
        is False,
    }
    if not all(checks.values()):
        raise RuntimeError(
            "required-unsupported matrix resource audit failed: "
            + canonical(
                {
                    "failed": [
                        name for name, passed in checks.items() if not passed
                    ]
                }
            )
        )
    payload = {
        "version": (
            "FOUNDRY_REQUIRED_UNSUPPORTED_MATRIX_RESOURCE_AUDIT_V1"
        ),
        "status": "REQUIRED_UNSUPPORTED_MATRIX_RESOURCE_PASS",
        "limits": limits,
        "meter_selftest": meter_test,
        "receipt": receipt,
        "checks": checks,
        "integration": {
            "matrix_process_tree_metered": True,
            "production_integrated_arms": 6,
            "required_arms": 10,
        },
        "P3": {
            "strict_contract_batch_ready": False,
            "complete": False,
        },
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE108_REQUIRED_UNSUPPORTED_MATRIX_RESOURCE"
        f" status={payload['status']}"
        " arms=4 outcomes=92 meter=PASS"
        " integrated=6/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    main()
