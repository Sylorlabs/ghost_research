#!/usr/bin/env python3
"""Create or verify the calibration framework-mount freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/pareto_remediation_v7_freeze.json"
RECORDS = (
    "results/pareto_remediation_v6_freeze.json",
    "PARETO_REMEDIATION_LEDGER_V7.json",
    "arm_adapter_fixtures/FRAMEWORK_RUNTIME_MOUNT_PROTOCOL_V1.json",
    "independent_framework_runtime.py",
    "framework_runtime_mount.py",
    "phase89_framework_runtime_mount_conformance.py",
    "results/phase89_framework_runtime_mount_conformance.json",
    "phase90_framework_runtime_mount_resource_audit.py",
    "results/phase90_framework_runtime_mount_resource_audit.json",
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
        raise RuntimeError("Pareto remediation-v7 freeze already exists")
    mount = json.loads(
        (
            HERE / "results/phase89_framework_runtime_mount_conformance.json"
        ).read_text()
    )
    resources = json.loads(
        (
            HERE
            / "results/phase90_framework_runtime_mount_resource_audit.json"
        ).read_text()
    )
    if not (
        mount["status"] == "FRAMEWORK_RUNTIME_MOUNT_COMPONENT_PASS"
        and all(mount["checks"].values())
        and mount["integration"]["calibration_graphs_mounted"] == 23
        and mount["integration"][
            "calibration_operator_targets_executed"
        ]
        == 41
        and resources["status"]
        == "FRAMEWORK_RUNTIME_MOUNT_RESOURCE_COMPONENT_PASS"
        and all(resources["checks"].values())
        and mount["P3"]["complete"] is False
        and resources["P3"]["complete"] is False
        and mount["validation_v6_accessed"] is False
        and resources["validation_v6_accessed"] is False
    ):
        raise RuntimeError("remediation-v7 evidence invalid or inflated")
    records = rows()
    payload = {
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V7",
        "records": records,
        "records_sha256": records_digest(records),
        "classification": "POST_AUTHORIZATION_CALIBRATION_MOUNT_NO_HELDOUT",
        "phases": [89, 90],
        "calibration_graphs": 23,
        "unique_operators_executed": 41,
        "call_function_invocations_executed": 337,
        "framework_executions_per_arm": 69,
        "A3_A9_runtime_mount_component_ready": True,
        "per_artifact_contract_resource_assembly_ready": False,
        "production_integrated_arms": 2,
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
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V7",
        "classification": "POST_AUTHORIZATION_CALIBRATION_MOUNT_NO_HELDOUT",
        "phases": [89, 90],
        "calibration_graphs": 23,
        "unique_operators_executed": 41,
        "call_function_invocations_executed": 337,
        "framework_executions_per_arm": 69,
        "A3_A9_runtime_mount_component_ready": True,
        "per_artifact_contract_resource_assembly_ready": False,
        "production_integrated_arms": 2,
        "P3_complete": False,
        "current_prerequisites_passed": 4,
        "current_prerequisites_required": 6,
        "prospective_trial_authorized": False,
        "heldout_source_runtime_graph_or_outcome_accessed": False,
        "heldout_execution_observed": False,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("Pareto remediation-v7 freeze changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("Pareto remediation-v7 record order changed")
    if payload["records_sha256"] != records_digest(payload["records"]):
        raise RuntimeError("Pareto remediation-v7 record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"Pareto remediation-v7 mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_PARETO_REMEDIATION_V7_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
