#!/usr/bin/env python3
"""Create or verify the rejected reduced-ISAMORE route result."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/isamore_reduced_route_v1_freeze.json"
RECORDS = (
    "freeze_isamore_reduced_route_v1.py",
    "external_controls/isamore/core_intake_v1.json",
    "phase52_isamore_reduced_route_audit.py",
    "results/control_four_route_v1_freeze.json",
    "results/phase52_isamore_reduced_route_audit.json",
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
        raise RuntimeError("ISAMORE reduced-route freeze already exists")
    result = json.loads(
        (HERE / "results/phase52_isamore_reduced_route_audit.json").read_text()
    )
    if (
        result["status"] != "ISAMORE_REDUCED_ROUTE_REJECTED"
        or result["reduced_route_faithful"] is not False
        or result["control_executed"] is not False
    ):
        raise RuntimeError("ISAMORE reduced-route result is not expected")
    records = rows()
    payload = {
        "version": "FOUNDRY_ISAMORE_REDUCED_ROUTE_FREEZE_V1",
        "records": records,
        "records_sha256": digest(records),
        "classification": "EVIDENCE_BACKED_ROUTE_REJECTION",
        "reduced_route_faithful": False,
        "control_executed": False,
        "source_faithful_controls_reproduced": 3,
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text())
    expected = {
        "version": "FOUNDRY_ISAMORE_REDUCED_ROUTE_FREEZE_V1",
        "classification": "EVIDENCE_BACKED_ROUTE_REJECTION",
        "reduced_route_faithful": False,
        "control_executed": False,
        "source_faithful_controls_reproduced": 3,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("ISAMORE reduced-route classification changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("ISAMORE reduced-route record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("ISAMORE reduced-route digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"ISAMORE reduced-route mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ISAMORE_REDUCED_ROUTE_V1_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
