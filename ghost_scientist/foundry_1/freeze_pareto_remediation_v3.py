#!/usr/bin/env python3
"""Create or verify the offline-trace and horizon-clarification freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/pareto_remediation_v3_freeze.json"
RECORDS = (
    "results/pareto_remediation_v2_freeze.json",
    "PARETO_REMEDIATION_LEDGER_V3.json",
    "external_traces/LOCAL_TRACE_BYTE_PROTOCOL_V1.json",
    "external_traces/source/alibaba_clusterdata_ROOT_README.md",
    "external_traces/source/alibaba_GenTD26_README.md",
    "external_traces/source/alibaba_lora_request_trace.csv",
    "phase77_local_trace_provenance.py",
    "results/phase77_local_trace_provenance.json",
    "external_traces/OFFLINE_REPLAY_PROTOCOL_V1.json",
    "phase78_offline_trace_replay.py",
    "results/phase78_offline_trace_replay.json",
    "phase79_offline_trace_resource_audit.py",
    "results/phase79_offline_trace_resource_audit.json",
    "external_traces/HORIZON_UNIT_MAPPING_PROTOCOL_V1.json",
    "phase80_horizon_unit_mapping_audit.py",
    "results/phase80_horizon_unit_mapping_audit.json",
    "PARETO_HORIZON_CLARIFICATION_V1.json",
    "independent_horizon_clarification.py",
    "phase81_horizon_clarification_conformance.py",
    "results/phase81_horizon_clarification_conformance.json",
    "phase82_horizon_protocol_resource_audit.py",
    "results/phase82_horizon_protocol_resource_audit.json",
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
        raise RuntimeError("Pareto remediation-v3 freeze already exists")
    p77 = json.loads(
        (HERE / "results/phase77_local_trace_provenance.json").read_text()
    )
    p78 = json.loads(
        (HERE / "results/phase78_offline_trace_replay.json").read_text()
    )
    p79 = json.loads(
        (HERE / "results/phase79_offline_trace_resource_audit.json").read_text()
    )
    p80 = json.loads(
        (HERE / "results/phase80_horizon_unit_mapping_audit.json").read_text()
    )
    p81 = json.loads(
        (
            HERE
            / "results/phase81_horizon_clarification_conformance.json"
        ).read_text()
    )
    p82 = json.loads(
        (
            HERE / "results/phase82_horizon_protocol_resource_audit.json"
        ).read_text()
    )
    if not (
        p77["P2"]["trace_source_bytes_locally_frozen"] is True
        and p77["P2"]["complete"] is False
        and p78["P2"]["two_offline_parsers_pass"] is True
        and p78["P2"]["complete"] is False
        and p79["P3"]["complete"] is False
        and p80["P2"]["artifact_stream_N_star_justified"] is False
        and p81["P2"]["complete"] is True
        and p81["independent"]["checks_passed"]
        == p81["independent"]["checks_total"]
        == 18
        and p82["P3"]["complete"] is False
        and p81[
            "validation_v6_source_runtime_graph_or_outcome_accessed"
        ]
        is False
        and p82[
            "validation_v6_source_runtime_graph_or_outcome_accessed"
        ]
        is False
    ):
        raise RuntimeError("remediation-v3 evidence invalid or inflated")
    records = rows()
    payload = {
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V3",
        "records": records,
        "records_sha256": records_digest(records),
        "classification": "POST_AUTHORIZATION_P2_REMEDIATION_NO_HELDOUT",
        "phases": [77, 78, 79, 80, 81, 82],
        "artifact_coordinate": 4,
        "invocations_per_artifact": 3,
        "execution_events": 12,
        "P2_complete": True,
        "P3_complete": False,
        "prerequisites_completed": 1,
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
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V3",
        "classification": "POST_AUTHORIZATION_P2_REMEDIATION_NO_HELDOUT",
        "phases": [77, 78, 79, 80, 81, 82],
        "artifact_coordinate": 4,
        "invocations_per_artifact": 3,
        "execution_events": 12,
        "P2_complete": True,
        "P3_complete": False,
        "prerequisites_completed": 1,
        "current_prerequisites_passed": 4,
        "current_prerequisites_required": 6,
        "prospective_trial_authorized": False,
        "heldout_source_runtime_graph_or_outcome_accessed": False,
        "heldout_execution_observed": False,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("Pareto remediation-v3 freeze changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("Pareto remediation-v3 record order changed")
    if payload["records_sha256"] != records_digest(payload["records"]):
        raise RuntimeError("Pareto remediation-v3 record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"Pareto remediation-v3 mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_PARETO_REMEDIATION_V3_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
