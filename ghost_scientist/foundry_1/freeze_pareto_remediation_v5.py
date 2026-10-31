#!/usr/bin/env python3
"""Create or verify the bounded A3/A9 adapter freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/pareto_remediation_v5_freeze.json"
RECORDS = (
    "results/pareto_remediation_v4_freeze.json",
    "PARETO_REMEDIATION_LEDGER_V5.json",
    "arm_adapter_fixtures/STATE_RESET_TYPED_DAG_PROTOCOL_V1.json",
    "arm_adapter_fixtures/state_reset_typed_dag_v1.json",
    "arm_adapter_fixtures/state_reset_A3_input_v1.json",
    "arm_adapter_fixtures/state_reset_A9_input_v1.json",
    "typed_dag_artifact.py",
    "independent_state_reset_adapter.py",
    "state_reset_arm_adapter.py",
    "phase85_state_reset_adapter_conformance.py",
    "results/phase85_state_reset_adapter_conformance.json",
    "phase86_state_reset_adapter_resource_audit.py",
    "results/phase86_state_reset_adapter_resource_audit.json",
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
        raise RuntimeError("Pareto remediation-v5 freeze already exists")
    conformance = json.loads(
        (
            HERE / "results/phase85_state_reset_adapter_conformance.json"
        ).read_text()
    )
    resources = json.loads(
        (
            HERE / "results/phase86_state_reset_adapter_resource_audit.json"
        ).read_text()
    )
    if not (
        conformance["status"]
        == "STATE_RESET_ADAPTER_BOUNDED_CONFORMANCE_PASS"
        and all(conformance["checks"].values())
        and len(conformance["hostile_rejections"]) == 9
        and conformance["integration"][
            "A3_typed_dag_adapter_implemented"
        ]
        is True
        and conformance["integration"][
            "A9_typed_dag_adapter_implemented"
        ]
        is True
        and conformance["integration"]["production_integrated_arms"] == 2
        and conformance["P3"]["complete"] is False
        and resources["status"]
        == "STATE_RESET_ADAPTER_RESOURCE_COMPONENT_PASS"
        and all(resources["checks"].values())
        and resources["P3"]["complete"] is False
        and resources["production_integrated_arms"] == 2
        and conformance["validation_v6_accessed"] is False
        and resources["validation_v6_accessed"] is False
    ):
        raise RuntimeError("remediation-v5 evidence invalid or inflated")
    records = rows()
    payload = {
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V5",
        "records": records,
        "records_sha256": records_digest(records),
        "classification": "POST_AUTHORIZATION_BOUNDED_A3_A9_NO_HELDOUT",
        "phases": [85, 86],
        "A3_bounded_adapter_ready": True,
        "A9_bounded_adapter_ready": True,
        "bounded_operator_count": 3,
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
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V5",
        "classification": "POST_AUTHORIZATION_BOUNDED_A3_A9_NO_HELDOUT",
        "phases": [85, 86],
        "A3_bounded_adapter_ready": True,
        "A9_bounded_adapter_ready": True,
        "bounded_operator_count": 3,
        "production_integrated_arms": 2,
        "P3_complete": False,
        "current_prerequisites_passed": 4,
        "current_prerequisites_required": 6,
        "prospective_trial_authorized": False,
        "heldout_source_runtime_graph_or_outcome_accessed": False,
        "heldout_execution_observed": False,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("Pareto remediation-v5 freeze changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("Pareto remediation-v5 record order changed")
    if payload["records_sha256"] != records_digest(payload["records"]):
        raise RuntimeError("Pareto remediation-v5 record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"Pareto remediation-v5 mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_PARETO_REMEDIATION_V5_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
