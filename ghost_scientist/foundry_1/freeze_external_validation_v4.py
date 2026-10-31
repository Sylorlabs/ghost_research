#!/usr/bin/env python3
"""Create or verify the pre-forge validation-v4 source and runtime freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/external_validation_v4_freeze.json"
RECORDS = (
    "freeze_external_validation_v4.py",
    "external_validation_v4/SOURCE_INTAKE.json",
    "external_validation_v4_runtime.py",
    "external_validation_v4/LICENSE.PyHealth",
    "external_validation_v4/LICENSE.DeepRobust",
    "external_workloads/LICENSE.pytorch-examples",
    "external_validation_v4/pyhealth_graph_model.py",
    "external_validation_v4/deeprobust_gaussian_model.py",
    "external_validation_v4/parameter_server_model.py",
    "external_validation_v4/distributed_linear_model.py",
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
        raise RuntimeError("validation-v4 freeze already exists")
    records = rows()
    payload = {
        "version": "FOUNDRY_EXTERNAL_VALIDATION_FREEZE_V4",
        "records": records,
        "records_sha256": digest(records),
        "boundary": {
            "polymorphic_forge_executed": False,
            "polymorphic_tool_records_observed": False,
            "validation_execution_observed": False,
            "runtime_harness_frozen": True,
            "input_shapes_seed_frozen": True,
            "validation_v3_reused": False,
            "repositories": 3,
            "transformer_architecture": False,
            "attention_operation": False,
        },
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if payload["version"] != "FOUNDRY_EXTERNAL_VALIDATION_FREEZE_V4":
        raise RuntimeError("validation-v4 freeze version changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("validation-v4 record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("validation-v4 record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"validation-v4 mismatch: {row['path']}")
    expected = {
        "polymorphic_forge_executed": False,
        "polymorphic_tool_records_observed": False,
        "validation_execution_observed": False,
        "runtime_harness_frozen": True,
        "input_shapes_seed_frozen": True,
        "validation_v3_reused": False,
        "repositories": 3,
        "transformer_architecture": False,
        "attention_operation": False,
    }
    if payload["boundary"] != expected:
        raise RuntimeError("validation-v4 boundary changed")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_EXTERNAL_VALIDATION_V4_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" records_sha256={payload['records_sha256']}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
