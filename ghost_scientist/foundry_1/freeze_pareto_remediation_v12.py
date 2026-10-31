#!/usr/bin/env python3
"""Create or verify the A7 direct-compatibility rejection freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/pareto_remediation_v12_freeze.json"
RECORDS = (
    "results/pareto_remediation_v11_freeze.json",
    "PARETO_REMEDIATION_LEDGER_V12.json",
    "arm_adapter_fixtures/A7_ENUMO_COMPATIBILITY_PROTOCOL_V1.json",
    "phase105_a7_enumo_compatibility_audit.py",
    "results/phase105_a7_enumo_compatibility_audit.json",
    "phase106_a7_enumo_compatibility_resource_audit.py",
    "results/phase106_a7_enumo_compatibility_resource_audit.json",
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
        raise RuntimeError("Pareto remediation-v12 freeze already exists")
    audit = json.loads(
        (
            HERE / "results/phase105_a7_enumo_compatibility_audit.json"
        ).read_text()
    )
    resource = json.loads(
        (
            HERE / "results/phase106_a7_enumo_compatibility_resource_audit.json"
        ).read_text()
    )
    if not (
        audit["status"] == "A7_DIRECT_ADAPTER_REJECTED"
        and all(audit["checks"].values())
        and audit["framework_surface"]["direct_call_matches"] == 0
        and audit["framework_surface"]["unsupported_calls"] == 337
        and audit["compatibility"]["direct_adapter_possible"] is False
        and audit["integration"]["A7_production_integrated"] is False
        and audit["integration"]["production_integrated_arms"] == 6
        and resource["status"] == "A7_COMPATIBILITY_RESOURCE_PASS"
        and all(resource["checks"].values())
        and resource["integration"]["A7_production_integrated"] is False
        and resource["integration"]["production_integrated_arms"] == 6
        and audit["validation_v6_accessed"] is False
    ):
        raise RuntimeError("remediation-v12 evidence invalid or inflated")
    rows = records()
    payload = {
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V12",
        "records": rows,
        "records_sha256": records_digest(rows),
        "classification": (
            "POST_AUTHORIZATION_A7_DIRECT_ADAPTER_REJECTED_NO_HELDOUT"
        ),
        "phases": [105, 106],
        "A7_framework_graphs_audited": 23,
        "A7_framework_operator_targets": 41,
        "A7_framework_call_function_invocations": 337,
        "A7_direct_operator_target_matches": 0,
        "A7_direct_call_matches": 0,
        "A7_new_tensor_domain_component_classes_required": 8,
        "A7_source_conformance_preserved": True,
        "A7_metamorphic_rule_set_failure_preserved": True,
        "A7_direct_adapter_supported": False,
        "A7_production_integrated": False,
        "production_integrated_arms": 6,
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
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V12",
        "classification": (
            "POST_AUTHORIZATION_A7_DIRECT_ADAPTER_REJECTED_NO_HELDOUT"
        ),
        "phases": [105, 106],
        "A7_framework_graphs_audited": 23,
        "A7_framework_operator_targets": 41,
        "A7_framework_call_function_invocations": 337,
        "A7_direct_operator_target_matches": 0,
        "A7_direct_call_matches": 0,
        "A7_new_tensor_domain_component_classes_required": 8,
        "A7_source_conformance_preserved": True,
        "A7_metamorphic_rule_set_failure_preserved": True,
        "A7_direct_adapter_supported": False,
        "A7_production_integrated": False,
        "production_integrated_arms": 6,
        "required_arms": 10,
        "P3_complete": False,
        "current_prerequisites_passed": 4,
        "current_prerequisites_required": 6,
        "prospective_trial_authorized": False,
        "heldout_source_runtime_graph_or_outcome_accessed": False,
        "heldout_execution_observed": False,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("Pareto remediation-v12 freeze changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("Pareto remediation-v12 record order changed")
    if payload["records_sha256"] != records_digest(payload["records"]):
        raise RuntimeError("Pareto remediation-v12 record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"Pareto remediation-v12 mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_PARETO_REMEDIATION_V12_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
