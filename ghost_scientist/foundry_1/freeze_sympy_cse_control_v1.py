#!/usr/bin/env python3
"""Create or verify the pre-execution SymPy CSE control freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE / "arm_adapter_fixtures/SYMPY_CSE_CONTROL_PROTOCOL_V1.json"
)
MANIFEST = HERE / "results/sympy_cse_control_v1_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def create() -> dict[str, object]:
    protocol = json.loads(PROTOCOL.read_text())
    for row in protocol["local_provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"SymPy local provider mismatch: {row['path']}")
    if not (
        protocol["frozen_before_control_execution"] is True
        and protocol["control_identity"]["version"] == "1.13.1"
        and protocol["control_identity"]["llm_calls"] == 0
        and protocol["selection_boundary"][
            "substitution_selected_from_validation_outcomes"
        ]
        is False
        and protocol["selection_boundary"]["may_replace_isamore_as_A6"]
        is False
        and protocol["selection_boundary"][
            "may_increase_production_integrated_arm_count"
        ]
        is False
        and protocol["official_suite_gate"]["minimum_collected"] == 60
        and protocol["official_suite_gate"]["minimum_passed"] == 55
        and len(protocol["hostile_checks"]) == 10
        and protocol["claim_boundary"]["validation_v6_accessed"] is False
    ):
        raise RuntimeError("SymPy CSE protocol is not fail-closed")
    return {
        "version": "FOUNDRY_SYMPY_CSE_CONTROL_FREEZE_V1",
        "protocol_sha256": sha(PROTOCOL),
        "frozen_before_control_execution": True,
        "system": "SymPy common subexpression elimination",
        "distribution_version": "1.13.1",
        "official_tag": "sympy-1.13.1",
        "repository_provider_records":
        protocol["repository_provider_records"],
        "distribution_provider_records":
        protocol["distribution_provider_records"],
        "local_provider_records": protocol["local_provider_records"],
        "minimum_collected": 60,
        "minimum_passed": 55,
        "hostile_checks": 10,
        "may_replace_isamore_as_A6": False,
        "may_increase_production_integrated_arm_count": False,
        "may_close_P1_only_after_all_gates_pass": True,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }


def verify() -> dict[str, object]:
    payload = json.loads(MANIFEST.read_text())
    if not (
        payload["version"] == "FOUNDRY_SYMPY_CSE_CONTROL_FREEZE_V1"
        and payload["protocol_sha256"] == sha(PROTOCOL)
        and payload["frozen_before_control_execution"] is True
        and payload["distribution_version"] == "1.13.1"
        and payload["minimum_collected"] == 60
        and payload["minimum_passed"] == 55
        and payload["hostile_checks"] == 10
        and payload["may_replace_isamore_as_A6"] is False
        and payload["may_increase_production_integrated_arm_count"] is False
        and payload["validation_v6_accessed"] is False
        and payload["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("SymPy CSE pre-execution freeze changed")
    for row in payload["local_provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"frozen SymPy provider mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    if not existed:
        MANIFEST.write_text(
            json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
        )
    verify()
    print(
        "FOUNDRY_SYMPY_CSE_CONTROL_V1_FREEZE_PASS"
        f" mode={'VERIFY' if existed else 'CREATE'}"
        " validation_access=false"
    )


if __name__ == "__main__":
    main()
