#!/usr/bin/env python3
"""Create or verify the csv-closure census progression freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/isamore_dependency_bridge_v5_freeze.json"
RECORDS = (
    "results/isamore_dependency_bridge_v4_freeze.json",
    "phase115_isamore_csv_closure_census.py",
    "results/phase115_isamore_csv_closure_census.json",
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
        raise RuntimeError("ISAMORE dependency-bridge-v5 freeze exists")
    result = json.loads(
        (HERE / "results/phase115_isamore_csv_closure_census.json").read_text()
    )
    if not (
        result["status"] == "ISAMORE_CSV_CLOSURE_AUTHENTICATED_INCOMPLETE"
        and result["summary"]["locked_packages"] == 11
        and result["summary"]["exact_cached_archives"] == 7
        and result["summary"]["missing_exact_archives"] == 4
        and result["build_stop_after_phase"] == "csv"
        and result["control_executed"] is False
        and result["P1_complete"] is False
    ):
        raise RuntimeError("ISAMORE dependency-bridge-v5 evidence invalid")
    records = rows()
    payload = {
        "version": "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V5",
        "records": records,
        "records_sha256": digest(records),
        "classification": "CSV_LOCKED_CLOSURE_CENSUS_NO_STOP_ADVANCE",
        "phases": [115],
        "closure_root": "csv 1.4.0",
        "locked_packages": 11,
        "exact_cached_archives": 7,
        "missing_exact_archives": 4,
        "prior_stop": "csv",
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
        "version": "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V5",
        "classification": "CSV_LOCKED_CLOSURE_CENSUS_NO_STOP_ADVANCE",
        "phases": [115],
        "closure_root": "csv 1.4.0",
        "locked_packages": 11,
        "exact_cached_archives": 7,
        "missing_exact_archives": 4,
        "prior_stop": "csv",
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
        raise RuntimeError("ISAMORE dependency-bridge-v5 freeze changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("ISAMORE dependency-bridge-v5 record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("ISAMORE dependency-bridge-v5 digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"ISAMORE dependency-bridge-v5 mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_V5_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
