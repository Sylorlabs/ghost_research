#!/usr/bin/env python3
"""Create or verify the complete pre-forge polymorphic prospective freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/polymorphic_prospective_v1_freeze.json"
RECORDS = (
    "freeze_polymorphic_prospective_v1.py",
    "POLYMORPHIC_PROSPECTIVE_PROTOCOL_V1.json",
    "phase29_polymorphic_semantic_forge.py",
    "phase30_independent_polymorphic_evaluator.py",
    "phase31_polymorphic_native_dedup.py",
    "phase32_polymorphic_resource_audit.py",
    "resource_meter_v2.py",
    "phase26_independent_semantic_evaluator.py",
    "phase27_semantic_native_dedup.py",
    "external_validation_v2_2_runtime.py",
    "results/forged_semantic_tools.json",
    "results/semantic_result_v1_freeze.json",
    "results/external_validation_v4_freeze.json",
    "ATEN_FIXED_PORTFOLIO_V2.json",
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
        raise RuntimeError("polymorphic prospective freeze already exists")
    records = rows()
    payload = {
        "version": "FOUNDRY_POLYMORPHIC_PROSPECTIVE_FREEZE_V1",
        "records": records,
        "records_sha256": digest(records),
        "boundary": {
            "polymorphic_forge_executed": False,
            "polymorphic_tool_records_observed": False,
            "validation_execution_observed": False,
            "validation_v4_prefrozen": True,
            "evaluator_prefrozen": True,
            "native_audit_prefrozen": True,
            "resource_matrix_prefrozen": True,
            "llm_calls_allowed": 0,
            "manual_type_widenings_allowed": 0,
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
    if payload["version"] != "FOUNDRY_POLYMORPHIC_PROSPECTIVE_FREEZE_V1":
        raise RuntimeError("polymorphic prospective freeze version changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("polymorphic prospective record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("polymorphic prospective record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"polymorphic prospective mismatch: {row['path']}")
    expected = {
        "polymorphic_forge_executed": False,
        "polymorphic_tool_records_observed": False,
        "validation_execution_observed": False,
        "validation_v4_prefrozen": True,
        "evaluator_prefrozen": True,
        "native_audit_prefrozen": True,
        "resource_matrix_prefrozen": True,
        "llm_calls_allowed": 0,
        "manual_type_widenings_allowed": 0,
        "full_foundry_v6_authorized": False,
    }
    if payload["boundary"] != expected:
        raise RuntimeError("polymorphic prospective boundary changed")
    protocol = json.loads(
        (HERE / "POLYMORPHIC_PROSPECTIVE_PROTOCOL_V1.json").read_text()
    )
    if (
        protocol["validation"]["seed"] != 0xC0572026
        or protocol["constraint_inference"]["llm_calls"] != 0
        or protocol["constraint_inference"]["manual_type_widenings"] != 0
        or protocol["validation"]["validation_v3_reused"] is not False
    ):
        raise RuntimeError("polymorphic protocol boundary invalid")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_POLYMORPHIC_PROSPECTIVE_V1_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" records_sha256={payload['records_sha256']}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
