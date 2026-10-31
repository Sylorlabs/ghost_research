#!/usr/bin/env python3
"""Create or verify the disclosed SymPy execution-amendment freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
AMENDMENT = (
    HERE
    / "arm_adapter_fixtures/SYMPY_CSE_CONTROL_EXECUTION_AMENDMENT_V1.json"
)
MANIFEST = (
    HERE / "results/sympy_cse_control_execution_amendment_v1_freeze.json"
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def create() -> dict[str, object]:
    amendment = json.loads(AMENDMENT.read_text())
    for key in ["base_protocol", "base_freeze"]:
        row = amendment[key]
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"SymPy amendment provider mismatch: {key}")
    chronology = amendment["chronology"]
    accounting = amendment["clarified_expected_outcome_accounting"]
    boundary = amendment["claim_boundary"]
    if not (
        chronology["base_protocol_was_frozen_before_execution"] is True
        and chronology["initial_execution_reached_test_collection"] is False
        and chronology["amendment_is_pristine_preregistration"] is False
        and chronology["isolated_diagnostic_observed"]
        == {
            "ordinary_passes": 53,
            "source_declared_xfails": 8,
            "unexpected_failures": 0,
            "errors": 0,
            "xpasses": 0,
        }
        and amendment["unchanged_gates"][
            "minimum_accepted_expected_outcomes"
        ]
        == 55
        and accounting["source_declared_xfail_decorators_required"] == 8
        and accounting["pytest_classified_xfails_required"] == 8
        and accounting["ordinary_passes_required"] == 53
        and boundary["amendment_may_erase_initial_infrastructure_failure"]
        is False
        and boundary["validation_v6_accessed"] is False
    ):
        raise RuntimeError("SymPy execution amendment is not fail-closed")
    return {
        "version":
        "FOUNDRY_SYMPY_CSE_CONTROL_EXECUTION_AMENDMENT_FREEZE_V1",
        "amendment_sha256": sha(AMENDMENT),
        "base_protocol_sha256": amendment["base_protocol"]["sha256"],
        "base_freeze_sha256": amendment["base_freeze"]["sha256"],
        "ordinary_passes_required": 53,
        "source_declared_xfails_required": 8,
        "minimum_accepted_expected_outcomes": 55,
        "maximum_unexpected_failures": 0,
        "maximum_errors": 0,
        "xpasses_allowed": False,
        "pristine_preregistration": False,
        "initial_infrastructure_failure_preserved": True,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }


def verify() -> dict[str, object]:
    payload = json.loads(MANIFEST.read_text())
    if not (
        payload["version"]
        == "FOUNDRY_SYMPY_CSE_CONTROL_EXECUTION_AMENDMENT_FREEZE_V1"
        and payload["amendment_sha256"] == sha(AMENDMENT)
        and payload["ordinary_passes_required"] == 53
        and payload["source_declared_xfails_required"] == 8
        and payload["minimum_accepted_expected_outcomes"] == 55
        and payload["maximum_unexpected_failures"] == 0
        and payload["maximum_errors"] == 0
        and payload["xpasses_allowed"] is False
        and payload["pristine_preregistration"] is False
        and payload["initial_infrastructure_failure_preserved"] is True
        and payload["validation_v6_accessed"] is False
        and payload["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("SymPy execution amendment freeze changed")
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
        "FOUNDRY_SYMPY_CSE_EXECUTION_AMENDMENT_V1_FREEZE_PASS"
        f" mode={'VERIFY' if existed else 'CREATE'}"
        " pristine=false initial_failure=preserved"
    )


if __name__ == "__main__":
    main()
