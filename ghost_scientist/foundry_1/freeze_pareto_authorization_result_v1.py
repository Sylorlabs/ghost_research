#!/usr/bin/env python3
"""Create or verify the frozen Pareto authorization and remediation result."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/pareto_authorization_result_v1_freeze.json"
RECORDS = (
    "freeze_pareto_authorization_result_v1.py",
    "results/pareto_candidate_v1_freeze.json",
    "phase68_pareto_authorization_audit.py",
    "results/phase68_pareto_authorization_audit.json",
    "phase69_authorization_access_resource_audit.py",
    "results/phase69_authorization_access_resource_audit.json",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows() -> list[dict[str, str]]:
    return [{"path": path, "sha256": sha(HERE / path)} for path in RECORDS]


def digest(value: list[dict[str, str]]) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def create() -> dict:
    if MANIFEST.exists():
        raise RuntimeError("Pareto authorization result freeze already exists")
    auth = json.loads(
        (HERE / "results/phase68_pareto_authorization_audit.json").read_text()
    )
    access = json.loads(
        (
            HERE / "results/phase69_authorization_access_resource_audit.json"
        ).read_text()
    )
    if (
        auth["status"] != "PARETO_PROSPECTIVE_NOT_AUTHORIZED"
        or auth["prospective_trial_authorized"] is not False
        or auth["heldout_import_or_execution_observed"] is not False
        or access["status"] != "AUTHORIZATION_ACCESS_RESOURCE_PASS"
        or access["heldout_source_runtime_or_graph_accessed"] is not False
    ):
        raise RuntimeError("authorization result is not a sealed remediation")
    records = rows()
    payload = {
        "version": "FOUNDRY_PARETO_AUTHORIZATION_RESULT_FREEZE_V1",
        "records": records,
        "records_sha256": digest(records),
        "classification": "REMEDIATION_REQUIRED_NO_HELDOUT_EXECUTION",
        "prerequisites_passed": sum(auth["prerequisites"].values()),
        "prerequisites_required": len(auth["prerequisites"]),
        "required_arms_integrated": len(
            auth["production_integrated_required_arms"]
        ),
        "required_arms": len(auth["required_arms"]),
        "active_stop_conditions": sum(
            value is True for value in auth["stop_conditions"].values()
        ),
        "prospective_trial_authorized": False,
        "heldout_manifest_accessed": True,
        "heldout_source_runtime_or_graph_accessed": False,
        "heldout_execution_observed": False,
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text())
    expected = {
        "version": "FOUNDRY_PARETO_AUTHORIZATION_RESULT_FREEZE_V1",
        "classification": "REMEDIATION_REQUIRED_NO_HELDOUT_EXECUTION",
        "prerequisites_passed": 3,
        "prerequisites_required": 6,
        "required_arms_integrated": 2,
        "required_arms": 10,
        "active_stop_conditions": 2,
        "prospective_trial_authorized": False,
        "heldout_manifest_accessed": True,
        "heldout_source_runtime_or_graph_accessed": False,
        "heldout_execution_observed": False,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("Pareto authorization result changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("authorization result record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("authorization result record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"authorization result mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_PARETO_AUTHORIZATION_RESULT_V1_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
