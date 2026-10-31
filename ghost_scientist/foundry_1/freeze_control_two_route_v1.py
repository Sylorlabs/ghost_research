#!/usr/bin/env python3
"""Create or verify the control-two acquisition-route audit freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/control_two_route_v1_freeze.json"
RECORDS = (
    "freeze_control_two_route_v1.py",
    "phase40_control_two_route_audit.py",
    "results/phase40_control_two_route_audit.json",
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
        raise RuntimeError("control-two route freeze already exists")
    records = rows()
    payload = {
        "version": "FOUNDRY_CONTROL_TWO_ROUTE_FREEZE_V1",
        "records": records,
        "records_sha256": digest(records),
        "selected_route": "babble_popl23",
        "babble_dependencies_available": 13,
        "babble_dependencies_total": 21,
        "control_executed": False,
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text(encoding="utf-8"))
    expected = {
        "version": "FOUNDRY_CONTROL_TWO_ROUTE_FREEZE_V1",
        "selected_route": "babble_popl23",
        "babble_dependencies_available": 13,
        "babble_dependencies_total": 21,
        "control_executed": False,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("control-two route classification changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("control-two route record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("control-two route digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"control-two route mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_CONTROL_TWO_ROUTE_V1_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
