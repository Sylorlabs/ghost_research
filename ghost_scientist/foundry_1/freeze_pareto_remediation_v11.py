#!/usr/bin/env python3
"""Create or verify the complete A5 integration freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/pareto_remediation_v11_freeze.json"
RECORDS = (
    "results/pareto_remediation_v10_freeze.json",
    "PARETO_REMEDIATION_LEDGER_V11.json",
    "arm_adapter_fixtures/A5_STITCH_TYPED_GRAPH_PROTOCOL_V1.json",
    "a5_stitch_graph_encoder.py",
    "independent_a5_stitch_graph_encoder.py",
    "phase99_a5_stitch_typed_graph_audit.py",
    "results/phase99_a5_stitch_typed_graph_audit.json",
    "phase100_a5_stitch_typed_graph_resource_audit.py",
    "results/phase100_a5_stitch_typed_graph_resource_audit.json",
    "freeze_a5_stitch_calibration.py",
    "results/a5_stitch_calibration_library_v1.json",
    "arm_adapter_fixtures/A5_STITCH_RUNTIME_MOUNT_PROTOCOL_V1.json",
    "independent_stitch_expander.py",
    "independent_a5_stitch_semantics_audit.py",
    "a5_stitch_runtime_mount.py",
    "phase101_a5_stitch_runtime_conformance.py",
    "results/phase101_a5_stitch_runtime_conformance.json",
    "phase102_a5_stitch_runtime_resource_audit.py",
    "results/phase102_a5_stitch_runtime_resource_audit.json",
    "arm_adapter_fixtures/A5_SHARED_RESOURCE_BATCH_PROTOCOL_V1.json",
    "a5_shared_resource_batch.py",
    "independent_a5_shared_resource_batch.py",
    "phase103_a5_shared_resource_batch_conformance.py",
    "results/phase103_a5_shared_resource_batch_conformance.json",
    "phase104_a5_shared_resource_batch_resource_audit.py",
    "results/phase104_a5_shared_resource_batch_resource_audit.json",
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
        raise RuntimeError("Pareto remediation-v11 freeze already exists")
    typed = json.loads(
        (
            HERE / "results/phase99_a5_stitch_typed_graph_audit.json"
        ).read_text()
    )
    mount = json.loads(
        (
            HERE / "results/phase101_a5_stitch_runtime_conformance.json"
        ).read_text()
    )
    mount_resource = json.loads(
        (
            HERE / "results/phase102_a5_stitch_runtime_resource_audit.json"
        ).read_text()
    )
    batch = json.loads(
        (
            HERE / "results/phase103_a5_shared_resource_batch_conformance.json"
        ).read_text()
    )
    batch_resource = json.loads(
        (
            HERE
            / "results/phase104_a5_shared_resource_batch_resource_audit.json"
        ).read_text()
    )
    if not (
        typed["status"] == "A5_STITCH_TYPED_GRAPH_COMPONENT_PASS"
        and typed["observed"]["abstractions"] == 1
        and typed["observed"]["cost_change"] == 66458
        and mount["status"] == "A5_STITCH_RUNTIME_CONFORMANCE_PASS"
        and all(mount["checks"].values())
        and mount_resource["status"]
        == "A5_STITCH_RUNTIME_RESOURCE_COMPONENT_PASS"
        and all(mount_resource["checks"].values())
        and batch["status"] == "A5_SHARED_RESOURCE_BATCH_CONFORMANCE_PASS"
        and all(batch["checks"].values())
        and batch_resource["status"]
        == "A5_SHARED_RESOURCE_BATCH_RESOURCE_PASS"
        and all(batch_resource["checks"].values())
        and batch["integration"]["production_integrated_arms"] == 6
        and batch_resource["integration"]["production_integrated_arms"]
        == 6
        and batch["P3"]["complete"] is False
        and mount["validation_v6_accessed"] is False
        and batch["validation_v6_accessed"] is False
    ):
        raise RuntimeError("remediation-v11 evidence invalid or inflated")
    rows = records()
    payload = {
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V11",
        "records": rows,
        "records_sha256": records_digest(rows),
        "classification": (
            "POST_AUTHORIZATION_A5_STRUCTURAL_CONTROL_INTEGRATION_NO_HELDOUT"
        ),
        "phases": [99, 100, 101, 102, 103, 104],
        "A5_abstractions": 1,
        "A5_structural_rewrite_uses": 329,
        "A5_unabstracted_nonempty_kwargs_calls": 8,
        "A5_normalized_reconstructions": 23,
        "A5_raw_encoder_byte_reconstructions": 0,
        "A5_whole_graph_executions": 69,
        "A5_maximum_error": 0.0,
        "A5_base_contract_pairs_accepted": 23,
        "A5_shared_resource_receipts_charged": 1,
        "A5_hostile_batches_rejected_twice": 19,
        "A5_rewritten_tensor_runtime_executed": False,
        "A5_tensor_primitive_invented": False,
        "A5_heldout_generalization_measured": False,
        "A5_fixed_portfolio_beaten": False,
        "A5_production_integrated_calibration_structural_control": True,
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
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V11",
        "classification": (
            "POST_AUTHORIZATION_A5_STRUCTURAL_CONTROL_INTEGRATION_NO_HELDOUT"
        ),
        "phases": [99, 100, 101, 102, 103, 104],
        "A5_abstractions": 1,
        "A5_structural_rewrite_uses": 329,
        "A5_unabstracted_nonempty_kwargs_calls": 8,
        "A5_normalized_reconstructions": 23,
        "A5_raw_encoder_byte_reconstructions": 0,
        "A5_whole_graph_executions": 69,
        "A5_maximum_error": 0.0,
        "A5_base_contract_pairs_accepted": 23,
        "A5_shared_resource_receipts_charged": 1,
        "A5_hostile_batches_rejected_twice": 19,
        "A5_rewritten_tensor_runtime_executed": False,
        "A5_tensor_primitive_invented": False,
        "A5_heldout_generalization_measured": False,
        "A5_fixed_portfolio_beaten": False,
        "A5_production_integrated_calibration_structural_control": True,
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
        raise RuntimeError("Pareto remediation-v11 freeze changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("Pareto remediation-v11 record order changed")
    if payload["records_sha256"] != records_digest(payload["records"]):
        raise RuntimeError("Pareto remediation-v11 record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"Pareto remediation-v11 mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_PARETO_REMEDIATION_V11_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
