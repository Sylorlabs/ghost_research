#!/usr/bin/env python3
"""Create or verify the resource-complete unsupported-arm freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/pareto_remediation_v13_freeze.json"
RECORDS = (
    "results/pareto_remediation_v12_freeze.json",
    "PARETO_REMEDIATION_LEDGER_V13.json",
    "arm_adapter_fixtures/REQUIRED_UNSUPPORTED_MATRIX_PROTOCOL_V1.json",
    "phase107_required_unsupported_matrix_audit.py",
    "results/phase107_required_unsupported_matrix_audit.json",
    "phase108_required_unsupported_matrix_resource_audit.py",
    "results/phase108_required_unsupported_matrix_resource_audit.json",
    "arm_adapter_fixtures/REQUIRED_UNSUPPORTED_CONTRACT_BATCH_PROTOCOL_V1.json",
    "required_unsupported_contract_batch.py",
    "independent_required_unsupported_contract_batch.py",
    "phase109_required_unsupported_contract_conformance.py",
    "results/phase109_required_unsupported_contract_conformance.json",
    "phase110_required_unsupported_contract_resource_audit.py",
    "results/phase110_required_unsupported_contract_resource_audit.json",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def records() -> list[dict[str, str]]:
    return [{"path": path, "sha256": sha(HERE / path)} for path in RECORDS]


def records_digest(value: list[dict[str, str]]) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def create() -> dict:
    if MANIFEST.exists():
        raise RuntimeError("Pareto remediation-v13 freeze already exists")
    matrix = json.loads(
        (
            HERE / "results/phase107_required_unsupported_matrix_audit.json"
        ).read_text()
    )
    matrix_resource = json.loads(
        (
            HERE
            / "results/phase108_required_unsupported_matrix_resource_audit.json"
        ).read_text()
    )
    contract = json.loads(
        (
            HERE
            / "results/phase109_required_unsupported_contract_conformance.json"
        ).read_text()
    )
    contract_resource = json.loads(
        (
            HERE
            / "results/phase110_required_unsupported_contract_resource_audit.json"
        ).read_text()
    )
    if not (
        matrix["status"]
        == "REQUIRED_UNSUPPORTED_MATRIX_COMPONENT_PASS"
        and all(matrix["checks"].values())
        and len(matrix["outcomes"]) == 92
        and matrix_resource["status"]
        == "REQUIRED_UNSUPPORTED_MATRIX_RESOURCE_PASS"
        and all(matrix_resource["checks"].values())
        and contract["status"]
        == "REQUIRED_UNSUPPORTED_CONTRACT_CONFORMANCE_PASS"
        and all(contract["checks"].values())
        and len(contract["hostile_rejections"]) == 25
        and all(
            row["rejected_twice"]
            for row in contract["hostile_rejections"]
        )
        and contract["P3"]["complete"] is True
        and contract_resource["status"]
        == "REQUIRED_UNSUPPORTED_CONTRACT_RESOURCE_PASS"
        and all(contract_resource["checks"].values())
        and contract_resource["P3"]["complete"] is True
        and contract_resource["integration"][
            "newly_production_integrated_arms"
        ]
        == 0
        and contract_resource["integration"][
            "production_integrated_arms"
        ]
        == 6
        and contract["validation_v6_accessed"] is False
    ):
        raise RuntimeError("remediation-v13 evidence invalid or inflated")
    rows = records()
    measured_cpu = contract["primary"]["allocated_cpu_ns"]
    payload = {
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V13",
        "records": rows,
        "records_sha256": records_digest(rows),
        "classification": (
            "POST_AUTHORIZATION_RESOURCE_COMPLETE_UNSUPPORTED_MATRIX_"
            "NO_HELDOUT"
        ),
        "phases": [107, 108, 109, 110],
        "explicit_required_unsupported_arms": ["A1", "A6", "A7", "A8"],
        "artifacts_per_arm": 23,
        "required_unsupported_contract_pairs": 92,
        "base_contract_primary_accepts": 92,
        "base_contract_independent_accepts": 92,
        "shared_resource_receipts_charged": 1,
        "measured_and_allocated_cpu_ns": measured_cpu,
        "cpu_charged_bindings": 4,
        "hostile_batches_rejected_twice": 25,
        "newly_conformant_arms": 0,
        "newly_production_integrated_arms": 0,
        "production_integrated_arms": 6,
        "required_arms": 10,
        "P3_complete": True,
        "current_prerequisites_passed": 5,
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
    fixed = {
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V13",
        "classification": (
            "POST_AUTHORIZATION_RESOURCE_COMPLETE_UNSUPPORTED_MATRIX_"
            "NO_HELDOUT"
        ),
        "phases": [107, 108, 109, 110],
        "explicit_required_unsupported_arms": ["A1", "A6", "A7", "A8"],
        "artifacts_per_arm": 23,
        "required_unsupported_contract_pairs": 92,
        "base_contract_primary_accepts": 92,
        "base_contract_independent_accepts": 92,
        "shared_resource_receipts_charged": 1,
        "cpu_charged_bindings": 4,
        "hostile_batches_rejected_twice": 25,
        "newly_conformant_arms": 0,
        "newly_production_integrated_arms": 0,
        "production_integrated_arms": 6,
        "required_arms": 10,
        "P3_complete": True,
        "current_prerequisites_passed": 5,
        "current_prerequisites_required": 6,
        "prospective_trial_authorized": False,
        "heldout_source_runtime_graph_or_outcome_accessed": False,
        "heldout_execution_observed": False,
    }
    if any(payload[key] != value for key, value in fixed.items()):
        raise RuntimeError("Pareto remediation-v13 freeze changed")
    if (
        type(payload["measured_and_allocated_cpu_ns"]) is not int
        or payload["measured_and_allocated_cpu_ns"] <= 0
    ):
        raise RuntimeError("Pareto remediation-v13 CPU changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("Pareto remediation-v13 record order changed")
    if payload["records_sha256"] != records_digest(payload["records"]):
        raise RuntimeError("Pareto remediation-v13 record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"Pareto remediation-v13 mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_PARETO_REMEDIATION_V13_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
