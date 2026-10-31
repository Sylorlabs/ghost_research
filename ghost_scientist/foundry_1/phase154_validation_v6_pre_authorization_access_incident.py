#!/usr/bin/env python3
"""Seal the fail-closed validation-v6 pre-authorization access incident."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULT = (
    HERE / "results/phase154_validation_v6_pre_authorization_access_incident.json"
)
INTEGRATION = (
    HERE / "results/phase153_a8_adapted_strategy_runtime_contract.json"
)
RUNTIME = HERE / "external_validation_v6_runtime.py"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    integration = json.loads(INTEGRATION.read_text())
    if not (
        integration["status"]
        == "A8_ADAPTED_STRATEGY_RUNTIME_CONTRACT_PASS"
        and integration["integration"]["production_integrated_arms"] == 10
        and integration["validation_v6_accessed"] is False
    ):
        raise RuntimeError("A8 integration input changed")
    payload = {
        "version": "FOUNDRY_VALIDATION_V6_PREAUTH_ACCESS_INCIDENT_V1",
        "status": "VALIDATION_V6_PROSPECTIVE_CHRONOLOGY_INVALIDATED",
        "detected_after_production_arm_integration": True,
        "production_integration": {
            "required_arms_integrated": 10,
            "required_arms": 10,
            "calibration_integration_remains_valid": True,
            "phase153_sha256": sha(INTEGRATION),
        },
        "access": {
            "path": RUNTIME.name,
            "sha256": sha(RUNTIME),
            "content_opened_before_new_authorization_record": True,
            "runtime_module_imported": False,
            "workloads_instantiated": False,
            "models_source_opened": False,
            "graphs_exported": False,
            "workloads_executed": False,
            "outcomes_observed": False,
        },
        "effects": {
            "validation_v6_may_be_used_for_prospective_claim": False,
            "P6_unchanged_prospective_freeze_for_v6": False,
            "V08_real_measurement_executed": False,
            "V08_measurement_passed": False,
            "prospective_trial_authorized": False,
            "prospective_trial_executed": False,
            "calibration_A6_or_A8_results_invalidated": False,
        },
        "required_remediation": {
            "route": "freeze a fresh validation-v7 corpus whose source runtime graph and outcomes remain unread until a new independent authorization pass",
            "must_not_reuse_v6_for_primary_prospective_claim": True,
            "must_preserve_v6_incident_permanently": True,
            "must_refreeze_seed_adapters_evaluator_and_V08_pairing_for_v7": True,
        },
        "claim_boundary": (
            "This incident invalidates validation-v6 prospective chronology, "
            "not the already completed calibration arm contracts. No v6 "
            "runtime, graph, numerical, search, or scientific outcome was "
            "executed or observed."
        ),
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE154_VALIDATION_V6_INCIDENT"
        " status=VALIDATION_V6_PROSPECTIVE_CHRONOLOGY_INVALIDATED"
        " integrated=10/10 executed=false outcomes=false authorized=false"
    )


if __name__ == "__main__":
    main()
