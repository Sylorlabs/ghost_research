#!/usr/bin/env python3
"""Create or verify the shared-resource batch freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/pareto_remediation_v8_freeze.json"
RECORDS = (
    "results/pareto_remediation_v7_freeze.json",
    "PARETO_REMEDIATION_LEDGER_V8.json",
    "arm_adapter_fixtures/SHARED_RESOURCE_RECEIPT_OVERLAY_V1.json",
    "shared_resource_batch.py",
    "independent_shared_resource_batch.py",
    "phase91_shared_resource_batch_conformance.py",
    "results/phase91_shared_resource_batch_conformance.json",
    "phase92_shared_resource_batch_resource_audit.py",
    "results/phase92_shared_resource_batch_resource_audit.json",
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
        raise RuntimeError("Pareto remediation-v8 freeze already exists")
    batch = json.loads(
        (
            HERE / "results/phase91_shared_resource_batch_conformance.json"
        ).read_text()
    )
    resources = json.loads(
        (
            HERE
            / "results/phase92_shared_resource_batch_resource_audit.json"
        ).read_text()
    )
    if not (
        batch["status"] == "SHARED_RESOURCE_BATCH_CONFORMANCE_PASS"
        and all(batch["checks"].values())
        and batch["integration"]["production_integrated_arms"] == 4
        and resources["status"] == "SHARED_RESOURCE_BATCH_RESOURCE_PASS"
        and all(resources["checks"].values())
        and resources["integration"]["production_integrated_arms"] == 4
        and batch["P3"]["complete"] is False
        and resources["P3"]["complete"] is False
        and batch["validation_v6_accessed"] is False
        and resources["validation_v6_accessed"] is False
    ):
        raise RuntimeError("remediation-v8 evidence invalid or inflated")
    records = rows()
    payload = {
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V8",
        "records": records,
        "records_sha256": records_digest(records),
        "classification": "POST_AUTHORIZATION_CONTRACT_BATCH_NO_HELDOUT",
        "phases": [91, 92],
        "base_contract_pairs_accepted": 46,
        "shared_resource_receipts_charged": 2,
        "hostile_batches_rejected_twice": 9,
        "A3_A9_production_integrated_calibration_arms": True,
        "production_integrated_arms": 4,
        "required_arms": 10,
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
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V8",
        "classification": "POST_AUTHORIZATION_CONTRACT_BATCH_NO_HELDOUT",
        "phases": [91, 92],
        "base_contract_pairs_accepted": 46,
        "shared_resource_receipts_charged": 2,
        "hostile_batches_rejected_twice": 9,
        "A3_A9_production_integrated_calibration_arms": True,
        "production_integrated_arms": 4,
        "required_arms": 10,
        "P3_complete": False,
        "current_prerequisites_passed": 4,
        "current_prerequisites_required": 6,
        "prospective_trial_authorized": False,
        "heldout_source_runtime_graph_or_outcome_accessed": False,
        "heldout_execution_observed": False,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("Pareto remediation-v8 freeze changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("Pareto remediation-v8 record order changed")
    if payload["records_sha256"] != records_digest(payload["records"]):
        raise RuntimeError("Pareto remediation-v8 record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"Pareto remediation-v8 mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_PARETO_REMEDIATION_V8_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
