#!/usr/bin/env python3
"""Create or verify the calibration operator-route freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/pareto_remediation_v6_freeze.json"
RECORDS = (
    "results/pareto_remediation_v5_freeze.json",
    "PARETO_REMEDIATION_LEDGER_V6.json",
    "arm_adapter_fixtures/CALIBRATION_OPERATOR_VOCAB_PROTOCOL_V1.json",
    "phase87_calibration_operator_vocabulary_audit.py",
    "results/phase87_calibration_operator_vocabulary_audit.json",
    "phase88_calibration_operator_vocabulary_resource_audit.py",
    "results/phase88_calibration_operator_vocabulary_resource_audit.json",
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
        raise RuntimeError("Pareto remediation-v6 freeze already exists")
    audit = json.loads(
        (
            HERE / "results/phase87_calibration_operator_vocabulary_audit.json"
        ).read_text()
    )
    resources = json.loads(
        (
            HERE
            / "results/phase88_calibration_operator_vocabulary_resource_audit.json"
        ).read_text()
    )
    summary = audit["summary"]
    if not (
        audit["status"]
        == "MANUAL_INTERPRETER_ROUTE_REJECTED_INCOMPLETE_SURFACE"
        and all(audit["checks"].values())
        and summary["graphs"] == 23
        and summary["unique_operators"] == 41
        and summary["call_function_invocations"] == 337
        and summary["bounded_unique_operators"] == 3
        and summary["bounded_invocations"] == 53
        and audit["decision"]["required_route"]
        == "EVALUATOR_SIDE_FRAMEWORK_RUNTIME_MOUNT"
        and resources["status"] == "OPERATOR_VOCAB_ROUTE_RESOURCE_PASS"
        and all(resources["checks"].values())
        and resources["P3"]["complete"] is False
        and audit["validation_v6_accessed"] is False
        and resources["validation_v6_accessed"] is False
    ):
        raise RuntimeError("remediation-v6 evidence invalid or inflated")
    records = rows()
    payload = {
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V6",
        "records": records,
        "records_sha256": records_digest(records),
        "classification": "POST_AUTHORIZATION_RUNTIME_ROUTE_NO_HELDOUT",
        "phases": [87, 88],
        "calibration_graphs": 23,
        "unique_operators": 41,
        "bounded_operator_count": 3,
        "required_runtime_route": "EVALUATOR_SIDE_FRAMEWORK_RUNTIME_MOUNT",
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
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V6",
        "classification": "POST_AUTHORIZATION_RUNTIME_ROUTE_NO_HELDOUT",
        "phases": [87, 88],
        "calibration_graphs": 23,
        "unique_operators": 41,
        "bounded_operator_count": 3,
        "required_runtime_route": "EVALUATOR_SIDE_FRAMEWORK_RUNTIME_MOUNT",
        "production_integrated_arms": 2,
        "P3_complete": False,
        "current_prerequisites_passed": 4,
        "current_prerequisites_required": 6,
        "prospective_trial_authorized": False,
        "heldout_source_runtime_graph_or_outcome_accessed": False,
        "heldout_execution_observed": False,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("Pareto remediation-v6 freeze changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("Pareto remediation-v6 record order changed")
    if payload["records_sha256"] != records_digest(payload["records"]):
        raise RuntimeError("Pareto remediation-v6 record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"Pareto remediation-v6 mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_PARETO_REMEDIATION_V6_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
