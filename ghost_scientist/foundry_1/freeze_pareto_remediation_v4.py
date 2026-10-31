#!/usr/bin/env python3
"""Create or verify the evaluator-owned arm-contract freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/pareto_remediation_v4_freeze.json"
RECORDS = (
    "results/pareto_remediation_v3_freeze.json",
    "PARETO_REMEDIATION_LEDGER_V4.json",
    "ARM_ADAPTER_CONTRACT_V1.json",
    "arm_adapter_contract.py",
    "independent_arm_adapter_contract.py",
    "phase83_arm_adapter_contract_conformance.py",
    "results/phase83_arm_adapter_contract_conformance.json",
    "phase84_arm_adapter_contract_resource_audit.py",
    "results/phase84_arm_adapter_contract_resource_audit.json",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows() -> list[dict[str, str]]:
    return [{"path": path, "sha256": sha(HERE / path)} for path in RECORDS]


def records_digest(records: list[dict[str, str]]) -> str:
    raw = json.dumps(records, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def create() -> dict:
    if MANIFEST.exists():
        raise RuntimeError("Pareto remediation-v4 freeze already exists")
    conformance = json.loads(
        (
            HERE / "results/phase83_arm_adapter_contract_conformance.json"
        ).read_text()
    )
    resources = json.loads(
        (
            HERE / "results/phase84_arm_adapter_contract_resource_audit.json"
        ).read_text()
    )
    if not (
        conformance["status"] == "ARM_ADAPTER_CONTRACT_CONFORMANCE_PASS"
        and all(conformance["checks"].values())
        and len(conformance["hostile_rejections"]) == 9
        and conformance["integration"]["required_arms_named"] == 10
        and conformance["integration"]["production_integrated_arms"] == 2
        and conformance["P3"]["complete"] is False
        and resources["status"] == "ARM_ADAPTER_CONTRACT_RESOURCE_PASS"
        and all(resources["checks"].values())
        and resources["P3"]["complete"] is False
        and conformance["validation_v6_accessed"] is False
        and resources["validation_v6_accessed"] is False
    ):
        raise RuntimeError("remediation-v4 evidence invalid or inflated")
    records = rows()
    payload = {
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V4",
        "records": records,
        "records_sha256": records_digest(records),
        "classification": "POST_AUTHORIZATION_ADAPTER_CONTRACT_NO_HELDOUT",
        "phases": [83, 84],
        "required_arms_named": 10,
        "production_integrated_arms": 2,
        "hostile_mutations_rejected_twice": 9,
        "P3_complete": False,
        "current_prerequisites_passed": 4,
        "current_prerequisites_required": 6,
        "prospective_trial_authorized": False,
        "heldout_source_runtime_graph_or_outcome_accessed": False,
        "heldout_execution_observed": False,
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text())
    expected = {
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V4",
        "classification": "POST_AUTHORIZATION_ADAPTER_CONTRACT_NO_HELDOUT",
        "phases": [83, 84],
        "required_arms_named": 10,
        "production_integrated_arms": 2,
        "hostile_mutations_rejected_twice": 9,
        "P3_complete": False,
        "current_prerequisites_passed": 4,
        "current_prerequisites_required": 6,
        "prospective_trial_authorized": False,
        "heldout_source_runtime_graph_or_outcome_accessed": False,
        "heldout_execution_observed": False,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("Pareto remediation-v4 freeze changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("Pareto remediation-v4 record order changed")
    if payload["records_sha256"] != records_digest(payload["records"]):
        raise RuntimeError("Pareto remediation-v4 record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"Pareto remediation-v4 mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_PARETO_REMEDIATION_V4_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
