#!/usr/bin/env python3
"""Create or verify the historical diversity-calibration result freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/diversity_calibration_v1_freeze.json"
RECORDS = (
    "freeze_diversity_calibration_v1.py",
    "phase53_diversity_calibration_audit.py",
    "phase54_diversity_calibration_resource_audit.py",
    "ATEN_FIXED_PORTFOLIO_V2.json",
    "results/phase53_diversity_calibration_audit.json",
    "results/phase54_diversity_calibration_resource_audit.json",
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
        raise RuntimeError("diversity calibration freeze already exists")
    result = json.loads(
        (HERE / "results/phase53_diversity_calibration_audit.json").read_text()
    )
    resource = json.loads(
        (
            HERE / "results/phase54_diversity_calibration_resource_audit.json"
        ).read_text()
    )
    if (
        result["status"] != "DIVERSITY_CALIBRATION_AUDIT_COMPLETE"
        or result["classification"]
        != "HISTORICAL_OUTCOMES_CALIBRATION_ONLY"
        or resource["status"] != "DIVERSITY_CALIBRATION_RESOURCE_PASS"
    ):
        raise RuntimeError("diversity calibration result is not expected")
    records = rows()
    payload = {
        "version": "FOUNDRY_DIVERSITY_CALIBRATION_FREEZE_V1",
        "records": records,
        "records_sha256": digest(records),
        "classification": "HISTORICAL_OUTCOMES_CALIBRATION_ONLY",
        "graphs": 19,
        "patterns_enumerated": 149,
        "selected_patterns": 11,
        "fixed_target_sequence_duplicates": 5,
        "novel_target_sequences": 6,
        "prospective_claim_allowed": False,
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text())
    expected = {
        "version": "FOUNDRY_DIVERSITY_CALIBRATION_FREEZE_V1",
        "classification": "HISTORICAL_OUTCOMES_CALIBRATION_ONLY",
        "graphs": 19,
        "patterns_enumerated": 149,
        "selected_patterns": 11,
        "fixed_target_sequence_duplicates": 5,
        "novel_target_sequences": 6,
        "prospective_claim_allowed": False,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("diversity calibration classification changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("diversity calibration record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("diversity calibration digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"diversity calibration mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_DIVERSITY_CALIBRATION_V1_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
