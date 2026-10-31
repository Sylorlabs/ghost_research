#!/usr/bin/env python3
"""Create or verify the pre-mining external validation source freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/external_validation_v1_freeze.json"
RECORDS = (
    "freeze_external_validation_v1.py",
    "external_workloads/LICENSE.pytorch-examples",
    "external_validation_v1/SOURCE_INTAKE.json",
    "external_validation_v1/regression_model.py",
    "external_validation_v1/actor_critic_model.py",
    "external_validation_v1/dcgan_model.py",
    "external_validation_v1/neural_style_model.py",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def record_rows() -> list[dict[str, str]]:
    return [{"path": path, "sha256": sha(HERE / path)} for path in RECORDS]


def rows_digest(rows: list[dict[str, str]]) -> str:
    raw = json.dumps(rows, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def create() -> dict:
    if MANIFEST.exists():
        raise RuntimeError("external validation v1 freeze already exists")
    rows = record_rows()
    payload = {
        "version": "FOUNDRY_EXTERNAL_VALIDATION_FREEZE_V1",
        "records": rows,
        "records_sha256": rows_digest(rows),
        "boundary": {
            "validation_execution_observed": False,
            "aten_forge_output_observed": False,
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
    if set(payload) != {"version", "records", "records_sha256", "boundary"}:
        raise RuntimeError("external validation v1 freeze fields changed")
    if payload["version"] != "FOUNDRY_EXTERNAL_VALIDATION_FREEZE_V1":
        raise RuntimeError("external validation v1 freeze version changed")
    if payload["records_sha256"] != rows_digest(payload["records"]):
        raise RuntimeError("external validation v1 records digest changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("external validation v1 record order changed")
    for row in payload["records"]:
        if set(row) != {"path", "sha256"} or sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"external validation v1 mismatch: {row['path']}")
    if payload["boundary"] != {
        "validation_execution_observed": False,
        "aten_forge_output_observed": False,
        "transformer_architecture": False,
        "attention_operation": False,
    }:
        raise RuntimeError("external validation v1 boundary changed")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_EXTERNAL_VALIDATION_V1_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" records_sha256={payload['records_sha256']}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
