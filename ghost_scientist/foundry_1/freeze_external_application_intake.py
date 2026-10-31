#!/usr/bin/env python3
"""Create or verify the pre-execution external application source freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/external_application_intake_freeze.json"
RECORDS = (
    "freeze_external_application_intake.py",
    "external_workloads/SOURCE_INTAKE.json",
    "external_workloads/LICENSE.pytorch-examples",
    "external_workloads/mnist_model.py",
    "external_workloads/vae_model.py",
    "external_workloads/sequence_model.py",
    "external_workloads/super_resolution_model.py",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def records() -> list[dict[str, str]]:
    return [{"path": item, "sha256": sha(HERE / item)} for item in RECORDS]


def digest(rows: list[dict[str, str]]) -> str:
    return hashlib.sha256(
        json.dumps(rows, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def create() -> dict:
    if MANIFEST.exists():
        raise RuntimeError("external application intake freeze already exists")
    rows = records()
    payload = {
        "version": "FOUNDRY_EXTERNAL_APPLICATION_INTAKE_FREEZE_V1",
        "records": rows,
        "records_sha256": digest(rows),
        "execution_observed": False,
        "outcomes_observed": False,
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if set(payload) != {
        "version",
        "records",
        "records_sha256",
        "execution_observed",
        "outcomes_observed",
    }:
        raise RuntimeError("external application intake freeze fields changed")
    if payload["version"] != "FOUNDRY_EXTERNAL_APPLICATION_INTAKE_FREEZE_V1":
        raise RuntimeError("external application intake freeze version changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("external application intake record digest changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("external application intake record order changed")
    for row in payload["records"]:
        if set(row) != {"path", "sha256"} or sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"external application intake mismatch: {row['path']}")
    if payload["execution_observed"] is not False or payload["outcomes_observed"] is not False:
        raise RuntimeError("external application intake was not pre-execution")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_EXTERNAL_APPLICATION_INTAKE_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" records_sha256={payload['records_sha256']}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
