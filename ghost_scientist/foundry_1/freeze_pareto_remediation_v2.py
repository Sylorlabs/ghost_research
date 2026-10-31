#!/usr/bin/env python3
"""Create or verify the invocation-trace remediation freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/pareto_remediation_v2_freeze.json"
RECORDS = (
    "results/pareto_remediation_v1_freeze.json",
    "PARETO_REMEDIATION_LEDGER_V2.json",
    "external_traces/INVOCATION_TRACE_INTAKE_V1.json",
    "external_traces/INVOCATION_TRACE_SCHEMA_FAILURE_V1.json",
    "external_traces/INVOCATION_TRACE_SCHEMA_AMENDMENT_V1.json",
    "external_traces/INVOCATION_TRACE_AGGREGATE_V1.json",
    "external_traces/INDEPENDENT_REPLAY_PROTOCOL_V1.json",
    "external_traces/INDEPENDENT_REPLAY_RECEIPT_V1.json",
    "external_traces/HORIZON_SENSITIVITY_PROTOCOL_V1.json",
    "phase74_external_invocation_trace_audit.py",
    "results/phase74_external_invocation_trace_audit.json",
    "phase75_external_trace_independent_replay.py",
    "results/phase75_external_trace_independent_replay.json",
    "phase76_external_horizon_sensitivity.py",
    "results/phase76_external_horizon_sensitivity.json",
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
        raise RuntimeError("Pareto remediation-v2 freeze already exists")
    p74 = json.loads(
        (HERE / "results/phase74_external_invocation_trace_audit.json").read_text()
    )
    p75 = json.loads(
        (HERE / "results/phase75_external_trace_independent_replay.json").read_text()
    )
    p76 = json.loads(
        (HERE / "results/phase76_external_horizon_sensitivity.json").read_text()
    )
    if not (
        p74["N_star_external_reference"] == 3
        and p74["P2"]["complete"] is False
        and p75["exact_relations_passed"] == p75["exact_relations_total"] == 12
        and p75["scientific_boundary"]["P2_complete"] is False
        and p76["primary"]["N"] == 3
        and p76["primary"]["candidate_strictly_lower"] is True
        and p76["P2"]["complete"] is False
        and p74["validation_v6_accessed"] is False
        and p76["validation_v6_accessed"] is False
    ):
        raise RuntimeError("trace remediation evidence overstates completion")
    records = rows()
    payload = {
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V2",
        "records": records,
        "records_sha256": records_digest(records),
        "classification": "POST_AUTHORIZATION_TRACE_REMEDIATION_NO_HELDOUT",
        "phases": [74, 75, 76],
        "external_N_star_reference": 3,
        "independent_replay_relations": 12,
        "P2_complete": False,
        "prerequisites_completed": 0,
        "prospective_trial_authorized": False,
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
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V2",
        "classification": "POST_AUTHORIZATION_TRACE_REMEDIATION_NO_HELDOUT",
        "phases": [74, 75, 76],
        "external_N_star_reference": 3,
        "independent_replay_relations": 12,
        "P2_complete": False,
        "prerequisites_completed": 0,
        "prospective_trial_authorized": False,
        "heldout_source_runtime_or_graph_accessed": False,
        "heldout_execution_observed": False,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("Pareto remediation-v2 freeze changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("Pareto remediation-v2 record order changed")
    if payload["records_sha256"] != records_digest(payload["records"]):
        raise RuntimeError("Pareto remediation-v2 record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"Pareto remediation-v2 mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_PARETO_REMEDIATION_V2_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
