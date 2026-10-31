#!/usr/bin/env python3
"""Create or verify the complete pre-execution ATen prospective-v2 freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/aten_prospective_v2_freeze.json"
RECORDS = (
    "freeze_aten_prospective_v2.py",
    "ATEN_PROSPECTIVE_PROTOCOL_V2.json",
    "ATEN_FIXED_PORTFOLIO_V2.json",
    "external_validation_v2_runtime.py",
    "phase21_prospective_aten_trial.py",
    "phase22_prospective_resource_audit.py",
    "independent_aten_tool_evaluator.py",
    "external_validation_runtime.py",
    "freeze_external_validation_v1.py",
    "results/external_validation_v1_freeze.json",
    "results/forged_aten_tools.json",
    "external_workloads/LICENSE.pytorch-examples",
    "external_validation_v2/SOURCE_INTAKE.json",
    "external_validation_v2/mnist_rnn_model.py",
    "external_validation_v2/reinforce_model.py",
    "external_validation_v2/gcn_model.py",
    "external_validation_v2/siamese_model.py",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows() -> list[dict[str, str]]:
    return [{"path": path, "sha256": sha(HERE / path)} for path in RECORDS]


def rows_sha(value: list[dict[str, str]]) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def create() -> dict:
    if MANIFEST.exists():
        raise RuntimeError("ATen prospective-v2 freeze already exists")
    records = rows()
    payload = {
        "version": "FOUNDRY_ATEN_PROSPECTIVE_FREEZE_V2",
        "records": records,
        "records_sha256": rows_sha(records),
        "boundary": {
            "v2_execution_observed": False,
            "v2_result_observed": False,
            "runtime_harness_frozen": True,
            "input_shapes_and_seed_frozen": True,
            "fixed_portfolio_frozen": True,
            "search_ledger_frozen": True,
            "resource_limits_frozen": True,
            "no_intervention_rule_frozen": True,
            "candidate_library_constructed_before_freeze": True,
            "candidate_aware_fixed_portfolio": True,
            "full_foundry_v6_authorized": False,
        },
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if payload["version"] != "FOUNDRY_ATEN_PROSPECTIVE_FREEZE_V2":
        raise RuntimeError("ATen prospective-v2 freeze version changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("ATen prospective-v2 freeze record order changed")
    if payload["records_sha256"] != rows_sha(payload["records"]):
        raise RuntimeError("ATen prospective-v2 record digest changed")
    for row in payload["records"]:
        if set(row) != {"path", "sha256"} or sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"ATen prospective-v2 mismatch: {row['path']}")
    expected_boundary = {
        "v2_execution_observed": False,
        "v2_result_observed": False,
        "runtime_harness_frozen": True,
        "input_shapes_and_seed_frozen": True,
        "fixed_portfolio_frozen": True,
        "search_ledger_frozen": True,
        "resource_limits_frozen": True,
        "no_intervention_rule_frozen": True,
        "candidate_library_constructed_before_freeze": True,
        "candidate_aware_fixed_portfolio": True,
        "full_foundry_v6_authorized": False,
    }
    if payload["boundary"] != expected_boundary:
        raise RuntimeError("ATen prospective-v2 boundary changed")
    protocol = json.loads((HERE / "ATEN_PROSPECTIVE_PROTOCOL_V2.json").read_text())
    if protocol["candidate_library"]["sha256"] != sha(
        HERE / protocol["candidate_library"]["path"]
    ):
        raise RuntimeError("protocol candidate digest mismatch")
    if protocol["workloads"]["seed"] != 0xF02D2026:
        raise RuntimeError("protocol seed mismatch")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ATEN_PROSPECTIVE_V2_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" records_sha256={payload['records_sha256']}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
