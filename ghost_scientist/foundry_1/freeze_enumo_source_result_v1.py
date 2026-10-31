#!/usr/bin/env python3
"""Create or verify the source-faithful Enumo result freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/enumo_source_result_v1_freeze.json"
RECORDS = (
    "freeze_enumo_source_result_v1.py",
    "phase45_enumo_source_control.py",
    "phase46_enumo_source_resource_audit.py",
    "results/phase45_enumo_source_control.json",
    "results/phase46_enumo_source_resource_audit.json",
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
        raise RuntimeError("Enumo source result freeze already exists")
    records = rows()
    payload = {
        "version": "FOUNDRY_ENUMO_SOURCE_RESULT_FREEZE_V1",
        "records": records,
        "records_sha256": digest(records),
        "classification": "SOURCE_FAITHFUL_CORE_CONTROL_WITH_BUILD_ADAPTATION",
        "official_boolean_conformance_passed": True,
        "full_official_crate_executed": False,
        "source_faithful_controls_reproduced": 3,
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text(encoding="utf-8"))
    expected = {
        "version": "FOUNDRY_ENUMO_SOURCE_RESULT_FREEZE_V1",
        "classification": "SOURCE_FAITHFUL_CORE_CONTROL_WITH_BUILD_ADAPTATION",
        "official_boolean_conformance_passed": True,
        "full_official_crate_executed": False,
        "source_faithful_controls_reproduced": 3,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("Enumo source result classification changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("Enumo source result record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("Enumo source result digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"Enumo source result mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ENUMO_SOURCE_RESULT_V1_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
