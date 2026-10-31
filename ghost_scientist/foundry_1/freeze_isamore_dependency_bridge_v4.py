#!/usr/bin/env python3
"""Create or verify the Crossbeam dependency-bridge progression."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/isamore_dependency_bridge_v4_freeze.json"
RECORDS = (
    "results/isamore_dependency_bridge_v3_freeze.json",
    "phase114_isamore_crossbeam_bridge_audit.py",
    "results/phase114_isamore_crossbeam_bridge_audit.json",
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
        raise RuntimeError("ISAMORE dependency-bridge-v4 freeze exists")
    result = json.loads(
        (
            HERE / "results/phase114_isamore_crossbeam_bridge_audit.json"
        ).read_text()
    )
    if not (
        result["status"] == "ISAMORE_CROSSBEAM_CLOSURE_ADVANCES_STOP"
        and result["checks"]["crossbeam_stop_cleared"] is True
        and result["checks"]["next_missing_package_authenticated"] is True
        and result["checks"]["algorithm_compilation_reached"] is False
        and result["checks"]["algorithm_execution_reached"] is False
        and result["next_build_stop"]["package"] == "csv"
        and result["control_executed"] is False
        and result["P1_complete"] is False
    ):
        raise RuntimeError("ISAMORE dependency-bridge-v4 evidence invalid")
    records = rows()
    payload = {
        "version": "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V4",
        "records": records,
        "records_sha256": digest(records),
        "classification": (
            "CROSSBEAM_MIXED_AUTHENTICATED_BRIDGE_NO_CONTROL_EXECUTION"
        ),
        "phases": [114],
        "bridged_package": "crossbeam",
        "bridged_version": "0.8.4",
        "prior_stop": "crossbeam",
        "next_stop": "csv",
        "algorithm_compilation_reached": False,
        "algorithm_execution_reached": False,
        "control_executed": False,
        "source_faithful_controls_reproduced": 3,
        "controls_required": 4,
        "P1_complete": False,
        "prospective_trial_authorized": False,
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text())
    fixed = {
        "version": "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V4",
        "classification": (
            "CROSSBEAM_MIXED_AUTHENTICATED_BRIDGE_NO_CONTROL_EXECUTION"
        ),
        "phases": [114],
        "bridged_package": "crossbeam",
        "bridged_version": "0.8.4",
        "prior_stop": "crossbeam",
        "next_stop": "csv",
        "algorithm_compilation_reached": False,
        "algorithm_execution_reached": False,
        "control_executed": False,
        "source_faithful_controls_reproduced": 3,
        "controls_required": 4,
        "P1_complete": False,
        "prospective_trial_authorized": False,
    }
    if any(payload[key] != value for key, value in fixed.items()):
        raise RuntimeError("ISAMORE dependency-bridge-v4 freeze changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("ISAMORE dependency-bridge-v4 record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("ISAMORE dependency-bridge-v4 digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"ISAMORE dependency-bridge-v4 mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_V4_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
