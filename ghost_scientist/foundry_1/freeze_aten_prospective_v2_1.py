#!/usr/bin/env python3
"""Create or verify the outcome-blind v2.1 infrastructure-remediation freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/aten_prospective_v2_1_freeze.json"
RECORDS = (
    "freeze_aten_prospective_v2_1.py",
    "ATEN_PROSPECTIVE_PROTOCOL_V2_1.json",
    "phase22_1_prospective_resource_audit.py",
    "resource_meter_v2.py",
    "results/aten_prospective_v2_freeze.json",
    "results/phase22_v2_infrastructure_failure.json",
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
        raise RuntimeError("v2.1 remediation freeze already exists")
    records = rows()
    payload = {
        "version": "FOUNDRY_ATEN_PROSPECTIVE_FREEZE_V2_1",
        "records": records,
        "records_sha256": digest(records),
        "boundary": {
            "candidate_outcomes_observed": False,
            "permitted_change": "METER_API_ONLY",
            "base_trial_unchanged": True,
            "v2_1_execution_observed": False,
        },
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if payload["version"] != "FOUNDRY_ATEN_PROSPECTIVE_FREEZE_V2_1":
        raise RuntimeError("v2.1 remediation freeze version changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("v2.1 record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("v2.1 record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"v2.1 mismatch: {row['path']}")
    if payload["boundary"] != {
        "candidate_outcomes_observed": False,
        "permitted_change": "METER_API_ONLY",
        "base_trial_unchanged": True,
        "v2_1_execution_observed": False,
    }:
        raise RuntimeError("v2.1 boundary changed")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ATEN_PROSPECTIVE_V2_1_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" records_sha256={payload['records_sha256']}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
