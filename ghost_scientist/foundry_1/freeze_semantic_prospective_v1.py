#!/usr/bin/env python3
"""Create or verify the complete pre-forge semantic prospective freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/semantic_prospective_v1_freeze.json"
RECORDS = (
    "freeze_semantic_prospective_v1.py",
    "SEMANTIC_TOOL_CONTRACT_V1.json",
    "SEMANTIC_PROSPECTIVE_PROTOCOL_V1.json",
    "ATEN_FIXED_PORTFOLIO_V2.json",
    "phase25_semantic_grammar_forge.py",
    "phase26_independent_semantic_evaluator.py",
    "phase27_semantic_native_dedup.py",
    "phase28_semantic_resource_audit.py",
    "resource_meter_v2.py",
    "independent_aten_tool_evaluator.py",
    "phase21_prospective_aten_trial.py",
    "external_validation_v2_2_runtime.py",
    "results/forged_aten_tools.json",
    "results/phase23_prospective_aten_trial_v2_2.json",
    "results/aten_prospective_v2_freeze.json",
    "results/aten_prospective_v2_2_freeze.json",
    "external_workloads/LICENSE.pytorch-examples",
    "external_validation_v3/SOURCE_INTAKE.json",
    "external_validation_v3_runtime.py",
    "external_validation_v3/hogwild_model.py",
    "external_validation_v3/forward_forward_layer.py",
    "external_validation_v3/ddp_toy_model.py",
    "external_validation_v3/rpc_decoder_model.py",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows() -> list[dict[str, str]]:
    return [{"path": path, "sha256": sha(HERE / path)} for path in RECORDS]


def rows_digest(value: list[dict[str, str]]) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def create() -> dict:
    if MANIFEST.exists():
        raise RuntimeError("semantic prospective-v1 freeze already exists")
    records = rows()
    payload = {
        "version": "FOUNDRY_SEMANTIC_PROSPECTIVE_FREEZE_V1",
        "records": records,
        "records_sha256": rows_digest(records),
        "boundary": {
            "semantic_forge_executed": False,
            "semantic_tool_records_observed": False,
            "validation_execution_observed": False,
            "validation_sources_frozen": True,
            "runtime_shapes_seed_frozen": True,
            "independent_evaluator_frozen": True,
            "native_dedup_frozen": True,
            "fixed_portfolio_frozen": True,
            "resource_matrix_frozen": True,
            "llm_calls_allowed": 0,
            "supplied_tool_forms": 0,
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
    if payload["version"] != "FOUNDRY_SEMANTIC_PROSPECTIVE_FREEZE_V1":
        raise RuntimeError("semantic prospective-v1 freeze version changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("semantic prospective-v1 record order changed")
    if payload["records_sha256"] != rows_digest(payload["records"]):
        raise RuntimeError("semantic prospective-v1 record digest changed")
    for row in payload["records"]:
        if set(row) != {"path", "sha256"} or sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"semantic prospective-v1 mismatch: {row['path']}")
    expected = {
        "semantic_forge_executed": False,
        "semantic_tool_records_observed": False,
        "validation_execution_observed": False,
        "validation_sources_frozen": True,
        "runtime_shapes_seed_frozen": True,
        "independent_evaluator_frozen": True,
        "native_dedup_frozen": True,
        "fixed_portfolio_frozen": True,
        "resource_matrix_frozen": True,
        "llm_calls_allowed": 0,
        "supplied_tool_forms": 0,
        "full_foundry_v6_authorized": False,
    }
    if payload["boundary"] != expected:
        raise RuntimeError("semantic prospective-v1 boundary changed")
    source = json.loads(
        (HERE / "external_validation_v3/SOURCE_INTAKE.json").read_text()
    )
    protocol = json.loads(
        (HERE / "SEMANTIC_PROSPECTIVE_PROTOCOL_V1.json").read_text()
    )
    if (
        source["selection_boundary"]["selected_before_semantic_tool_records_exist"]
        is not True
        or protocol["validation"]["seed"] != 0x5E6A2026
        or protocol["construction"]["llm_calls"] != 0
        or protocol["construction"]["supplied_tool_forms"] != 0
    ):
        raise RuntimeError("semantic prospective-v1 protocol boundary invalid")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_SEMANTIC_PROSPECTIVE_V1_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" records_sha256={payload['records_sha256']}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
