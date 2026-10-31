#!/usr/bin/env python3
"""Create or verify the pre-execution external-control protocol freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/external_control_execution_v1_freeze.json"
RECORDS = (
    "freeze_external_control_execution_v1.py",
    "CONTROL_EXECUTION_PROTOCOL_V1.json",
    "external_controls/stitch/conformance_fixture_v1.json",
    "phase33_stitch_control_conformance.py",
    "phase34_stitch_control_resource_audit.py",
    "resource_meter_v2.py",
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
        raise RuntimeError("external-control execution freeze already exists")
    records = rows()
    payload = {
        "version": "FOUNDRY_EXTERNAL_CONTROL_EXECUTION_FREEZE_V1",
        "records": records,
        "records_sha256": digest(records),
        "boundary": {
            "control_executed": False,
            "control_result_observed": False,
            "ghost_artifacts_visible_to_control": False,
            "missing_artifact_counts_as_reproduction": False,
            "local_reimplementation_allowed": False,
        },
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if payload["version"] != "FOUNDRY_EXTERNAL_CONTROL_EXECUTION_FREEZE_V1":
        raise RuntimeError("external-control freeze version changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("external-control record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("external-control record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"external-control mismatch: {row['path']}")
    expected = {
        "control_executed": False,
        "control_result_observed": False,
        "ghost_artifacts_visible_to_control": False,
        "missing_artifact_counts_as_reproduction": False,
        "local_reimplementation_allowed": False,
    }
    if payload["boundary"] != expected:
        raise RuntimeError("external-control boundary changed")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_EXTERNAL_CONTROL_EXECUTION_V1_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" records_sha256={payload['records_sha256']}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
