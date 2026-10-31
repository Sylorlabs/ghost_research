#!/usr/bin/env python3
"""Create or verify the evidence-backed fourth-control route freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/control_four_route_v1_freeze.json"
RECORDS = (
    "freeze_control_four_route_v1.py",
    "phase51_control_four_route_audit.py",
    "external_controls/isamore/source/README.md",
    "external_controls/isamore/source/Cargo.toml",
    "external_controls/isamore/source/.gitmodules",
    "external_controls/isamore/source/rust-toolchain.toml",
    "external_controls/isamore/source/template.toml",
    "external_controls/isamore/source/benchmarks-profile.toml",
    "results/phase51_control_four_route_audit.json",
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
        raise RuntimeError("fourth-control route freeze already exists")
    route = json.loads(
        (HERE / "results/phase51_control_four_route_audit.json").read_text()
    )
    if (
        route["status"] != "CONTROL_FOUR_ROUTE_SELECTED_NOT_EXECUTABLE"
        or route["route"]["system"] != "ISAMORE"
        or route["control_executed"] is not False
    ):
        raise RuntimeError("fourth-control route is not the expected boundary")
    records = rows()
    payload = {
        "version": "FOUNDRY_CONTROL_FOUR_ROUTE_FREEZE_V1",
        "records": records,
        "records_sha256": digest(records),
        "selected_route": "ISAMORE",
        "route_executable": False,
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
        "version": "FOUNDRY_CONTROL_FOUR_ROUTE_FREEZE_V1",
        "selected_route": "ISAMORE",
        "route_executable": False,
        "control_executed": False,
        "source_faithful_controls_reproduced": 3,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("fourth-control route classification changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("fourth-control route record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("fourth-control route digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"fourth-control route mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_CONTROL_FOUR_ROUTE_V1_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
