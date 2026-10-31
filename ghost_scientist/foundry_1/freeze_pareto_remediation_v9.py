#!/usr/bin/env python3
"""Create or verify the A1 IR compatibility freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/pareto_remediation_v9_freeze.json"
RECORDS = (
    "results/pareto_remediation_v8_freeze.json",
    "PARETO_REMEDIATION_LEDGER_V9.json",
    "arm_adapter_fixtures/A1_IR_COMPATIBILITY_PROTOCOL_V1.json",
    "independent_a1_ir_audit.py",
    "phase93_a1_ir_compatibility_audit.py",
    "results/phase93_a1_ir_compatibility_audit.json",
    "phase94_a1_ir_compatibility_resource_audit.py",
    "results/phase94_a1_ir_compatibility_resource_audit.json",
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
        raise RuntimeError("Pareto remediation-v9 freeze already exists")
    audit = json.loads(
        (
            HERE / "results/phase93_a1_ir_compatibility_audit.json"
        ).read_text()
    )
    resource = json.loads(
        (
            HERE / "results/phase94_a1_ir_compatibility_resource_audit.json"
        ).read_text()
    )
    if not (
        audit["status"]
        == "A1_DIRECT_ADAPTER_REJECTED_INCOMPLETE_IR_SURFACE"
        and all(audit["checks"].values())
        and audit["summary"]["graphs"] == 23
        and audit["summary"]["unique_operator_targets"] == 41
        and audit["summary"]["call_function_invocations"] == 337
        and audit["summary"]["whole_graph_direct"] == 4
        and audit["summary"]["exact_constructor_pattern_candidates"] == 0
        and audit["summary"]["production_adapter_ready"] is False
        and resource["status"] == "A1_IR_COMPATIBILITY_RESOURCE_PASS"
        and all(resource["checks"].values())
        and audit["integration"]["production_integrated_arms"] == 4
        and resource["integration"]["production_integrated_arms"] == 4
        and audit["validation_v6_accessed"] is False
        and resource["validation_v6_accessed"] is False
    ):
        raise RuntimeError("remediation-v9 evidence invalid or inflated")
    rows = records()
    payload = {
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V9",
        "records": rows,
        "records_sha256": records_digest(rows),
        "classification": "POST_AUTHORIZATION_A1_COMPATIBILITY_NO_HELDOUT",
        "phases": [93, 94],
        "A1_runtime_ops": 22,
        "direct_exact_ATen_targets": 9,
        "direct_exact_calls": 143,
        "whole_graphs_direct": 4,
        "exact_constructor_pattern_candidates": 0,
        "A1_production_integrated": False,
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
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V9",
        "classification": "POST_AUTHORIZATION_A1_COMPATIBILITY_NO_HELDOUT",
        "phases": [93, 94],
        "A1_runtime_ops": 22,
        "direct_exact_ATen_targets": 9,
        "direct_exact_calls": 143,
        "whole_graphs_direct": 4,
        "exact_constructor_pattern_candidates": 0,
        "A1_production_integrated": False,
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
        raise RuntimeError("Pareto remediation-v9 freeze changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("Pareto remediation-v9 record order changed")
    if payload["records_sha256"] != records_digest(payload["records"]):
        raise RuntimeError("Pareto remediation-v9 record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"Pareto remediation-v9 mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_PARETO_REMEDIATION_V9_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
