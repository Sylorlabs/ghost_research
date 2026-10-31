#!/usr/bin/env python3
"""Create or verify the complete A4 integration freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/pareto_remediation_v10_freeze.json"
RECORDS = (
    "results/pareto_remediation_v9_freeze.json",
    "PARETO_REMEDIATION_LEDGER_V10.json",
    "arm_adapter_fixtures/A4_REPLAY_RUNTIME_PROTOCOL_V1.json",
    "a4_replay_runtime_mount.py",
    "phase95_a4_replay_runtime_conformance.py",
    "results/phase95_a4_replay_runtime_conformance.json",
    "phase96_a4_replay_runtime_resource_audit.py",
    "results/phase96_a4_replay_runtime_resource_audit.json",
    "arm_adapter_fixtures/A4_SHARED_RESOURCE_BATCH_PROTOCOL_V1.json",
    "a4_shared_resource_batch.py",
    "independent_a4_shared_resource_batch.py",
    "phase97_a4_shared_resource_batch_conformance.py",
    "results/phase97_a4_shared_resource_batch_conformance.json",
    "phase98_a4_shared_resource_batch_resource_audit.py",
    "results/phase98_a4_shared_resource_batch_resource_audit.json",
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
        raise RuntimeError("Pareto remediation-v10 freeze already exists")
    mount = json.loads(
        (
            HERE / "results/phase95_a4_replay_runtime_conformance.json"
        ).read_text()
    )
    mount_resource = json.loads(
        (
            HERE / "results/phase96_a4_replay_runtime_resource_audit.json"
        ).read_text()
    )
    batch = json.loads(
        (
            HERE / "results/phase97_a4_shared_resource_batch_conformance.json"
        ).read_text()
    )
    batch_resource = json.loads(
        (
            HERE
            / "results/phase98_a4_shared_resource_batch_resource_audit.json"
        ).read_text()
    )
    if not (
        mount["status"] == "A4_REPLAY_RUNTIME_CONFORMANCE_PASS"
        and all(mount["checks"].values())
        and mount_resource["status"]
        == "A4_REPLAY_RUNTIME_RESOURCE_COMPONENT_PASS"
        and all(mount_resource["checks"].values())
        and batch["status"] == "A4_SHARED_RESOURCE_BATCH_CONFORMANCE_PASS"
        and all(batch["checks"].values())
        and batch_resource["status"]
        == "A4_SHARED_RESOURCE_BATCH_RESOURCE_PASS"
        and all(batch_resource["checks"].values())
        and batch["integration"]["production_integrated_arms"] == 5
        and batch_resource["integration"]["production_integrated_arms"]
        == 5
        and batch["P3"]["complete"] is False
        and mount["validation_v6_accessed"] is False
        and batch["validation_v6_accessed"] is False
    ):
        raise RuntimeError("remediation-v10 evidence invalid or inflated")
    rows = records()
    payload = {
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V10",
        "records": rows,
        "records_sha256": records_digest(rows),
        "classification": "POST_AUTHORIZATION_A4_INTEGRATION_NO_HELDOUT",
        "phases": [95, 96, 97, 98],
        "A4_immutable_tools": 3,
        "A4_successful_tool_replays": 29,
        "A4_whole_graph_executions": 69,
        "A4_maximum_error": 0.0,
        "A4_base_contract_pairs_accepted": 23,
        "A4_shared_resource_receipts_charged": 1,
        "A4_hostile_batches_rejected_twice": 11,
        "A4_production_integrated_calibration_arm": True,
        "production_integrated_arms": 5,
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
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V10",
        "classification": "POST_AUTHORIZATION_A4_INTEGRATION_NO_HELDOUT",
        "phases": [95, 96, 97, 98],
        "A4_immutable_tools": 3,
        "A4_successful_tool_replays": 29,
        "A4_whole_graph_executions": 69,
        "A4_maximum_error": 0.0,
        "A4_base_contract_pairs_accepted": 23,
        "A4_shared_resource_receipts_charged": 1,
        "A4_hostile_batches_rejected_twice": 11,
        "A4_production_integrated_calibration_arm": True,
        "production_integrated_arms": 5,
        "required_arms": 10,
        "P3_complete": False,
        "current_prerequisites_passed": 4,
        "current_prerequisites_required": 6,
        "prospective_trial_authorized": False,
        "heldout_source_runtime_graph_or_outcome_accessed": False,
        "heldout_execution_observed": False,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("Pareto remediation-v10 freeze changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("Pareto remediation-v10 record order changed")
    if payload["records_sha256"] != records_digest(payload["records"]):
        raise RuntimeError("Pareto remediation-v10 record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"Pareto remediation-v10 mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_PARETO_REMEDIATION_V10_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
