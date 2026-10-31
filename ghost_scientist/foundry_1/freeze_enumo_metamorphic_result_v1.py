#!/usr/bin/env python3
"""Create or verify the failed pre-frozen Enumo metamorphic result."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_enumo_metamorphic_v1 import verify as verify_prefreeze


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/enumo_metamorphic_result_v1_freeze.json"
RECORDS = (
    "freeze_enumo_metamorphic_result_v1.py",
    "results/enumo_metamorphic_v1_freeze.json",
    "phase48_enumo_metamorphic_resource_audit.py",
    "results/phase47_enumo_metamorphic_control.json",
    "results/phase48_enumo_metamorphic_resource_audit.json",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows() -> list[dict[str, str]]:
    return [{"path": path, "sha256": sha(HERE / path)} for path in RECORDS]


def digest(value: list[dict[str, str]]) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def create() -> dict:
    verify_prefreeze()
    if MANIFEST.exists():
        raise RuntimeError("Enumo metamorphic result freeze already exists")
    result = json.loads(
        (HERE / "results/phase47_enumo_metamorphic_control.json").read_text()
    )
    resource = json.loads(
        (
            HERE / "results/phase48_enumo_metamorphic_resource_audit.json"
        ).read_text()
    )
    if (
        result["metamorphic_relation_passed"] is not False
        or resource["receipt_complete"] is not True
    ):
        raise RuntimeError("Enumo failed-result evidence is not expected")
    records = rows()
    payload = {
        "version": "FOUNDRY_ENUMO_METAMORPHIC_RESULT_FREEZE_V1",
        "records": records,
        "records_sha256": digest(records),
        "classification": "PRE_FROZEN_METAMORPHIC_CONTROL_FAIL",
        "metamorphic_relation_passed": False,
        "execution_receipt_complete": True,
        "baseline_rules": 60,
        "transformed_rules": 67,
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    return payload


def verify() -> dict:
    verify_prefreeze()
    payload = json.loads(MANIFEST.read_text(encoding="utf-8"))
    expected = {
        "version": "FOUNDRY_ENUMO_METAMORPHIC_RESULT_FREEZE_V1",
        "classification": "PRE_FROZEN_METAMORPHIC_CONTROL_FAIL",
        "metamorphic_relation_passed": False,
        "execution_receipt_complete": True,
        "baseline_rules": 60,
        "transformed_rules": 67,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("Enumo failed-result classification changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("Enumo failed-result record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("Enumo failed-result digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"Enumo failed-result mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ENUMO_METAMORPHIC_RESULT_V1_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" outcome=FAIL"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
