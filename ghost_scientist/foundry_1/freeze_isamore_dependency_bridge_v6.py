#!/usr/bin/env python3
"""Create or verify the exact-tag csv bridge progression freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/isamore_dependency_bridge_v6_freeze.json"
RECORDS = (
    "results/isamore_dependency_bridge_v5_freeze.json",
    "phase116_isamore_csv_tag_bridge_audit.py",
    "results/phase116_isamore_csv_tag_bridge_audit.json",
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
        raise RuntimeError("ISAMORE dependency-bridge-v6 freeze exists")
    result = json.loads(
        (HERE / "results/phase116_isamore_csv_tag_bridge_audit.json").read_text()
    )
    if not (
        result["status"] == "ISAMORE_CSV_CLOSURE_ADVANCES_STOP"
        and len(result["bridge"]["official_tag_records"]) == 27
        and result["bridge"]["crates_io_tarball_checksums_authenticated"] is False
        and result["checks"]["csv_stop_cleared"] is True
        and result["next_build_stop"]["package"] == "env_logger"
        and result["control_executed"] is False
        and result["P1_complete"] is False
    ):
        raise RuntimeError("ISAMORE dependency-bridge-v6 evidence invalid")
    records = rows()
    payload = {
        "version": "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V6",
        "records": records,
        "records_sha256": digest(records),
        "classification": "CSV_EXACT_TAG_BRIDGE_NO_CONTROL_EXECUTION",
        "phases": [116],
        "bridged_packages": ["csv", "csv-core", "itoa", "quote"],
        "official_tag_records": 27,
        "prior_stop": "csv",
        "next_stop": "env_logger",
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
        "version": "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V6",
        "classification": "CSV_EXACT_TAG_BRIDGE_NO_CONTROL_EXECUTION",
        "phases": [116],
        "bridged_packages": ["csv", "csv-core", "itoa", "quote"],
        "official_tag_records": 27,
        "prior_stop": "csv",
        "next_stop": "env_logger",
        "algorithm_compilation_reached": False,
        "algorithm_execution_reached": False,
        "control_executed": False,
        "source_faithful_controls_reproduced": 3,
        "controls_required": 4,
        "P1_complete": False,
        "prospective_trial_authorized": False,
    }
    if any(payload[key] != value for key, value in fixed.items()):
        raise RuntimeError("ISAMORE dependency-bridge-v6 freeze changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("ISAMORE dependency-bridge-v6 record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("ISAMORE dependency-bridge-v6 digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"ISAMORE dependency-bridge-v6 mismatch: {row['path']}"
            )
    result = json.loads(
        (HERE / "results/phase116_isamore_csv_tag_bridge_audit.json").read_text()
    )
    for row in result["bridge"]["official_tag_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"ISAMORE dependency-bridge-v6 source mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_V6_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
