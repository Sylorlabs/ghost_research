#!/usr/bin/env python3
"""Create or verify the env_logger union-closure census freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/isamore_dependency_bridge_v7_freeze.json"
RECORDS = (
    "results/isamore_dependency_bridge_v6_freeze.json",
    "phase117_isamore_env_logger_closure_census.py",
    "results/phase117_isamore_env_logger_closure_census.json",
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
        raise RuntimeError("ISAMORE dependency-bridge-v7 freeze exists")
    result = json.loads(
        (
            HERE / "results/phase117_isamore_env_logger_closure_census.json"
        ).read_text()
    )
    if not (
        result["status"]
        == "ISAMORE_ENV_LOGGER_CLOSURE_AUTHENTICATED_INCOMPLETE"
        and result["summary"]["root_versions"] == 3
        and result["summary"]["locked_packages"] == 31
        and result["summary"]["exact_cached_archives"] == 14
        and result["summary"]["missing_exact_archives"] == 17
        and result["single_version_patch_rejected"] is True
        and result["build_stop_after_phase"] == "env_logger"
        and result["control_executed"] is False
    ):
        raise RuntimeError("ISAMORE dependency-bridge-v7 evidence invalid")
    records = rows()
    payload = {
        "version": "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V7",
        "records": records,
        "records_sha256": digest(records),
        "classification": "ENV_LOGGER_UNION_CLOSURE_CENSUS_NO_STOP_ADVANCE",
        "phases": [117],
        "root_versions": 3,
        "locked_packages": 31,
        "exact_cached_archives": 14,
        "missing_exact_archives": 17,
        "prior_stop": "env_logger",
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
        "version": "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V7",
        "classification": "ENV_LOGGER_UNION_CLOSURE_CENSUS_NO_STOP_ADVANCE",
        "phases": [117],
        "root_versions": 3,
        "locked_packages": 31,
        "exact_cached_archives": 14,
        "missing_exact_archives": 17,
        "prior_stop": "env_logger",
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
        raise RuntimeError("ISAMORE dependency-bridge-v7 freeze changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("ISAMORE dependency-bridge-v7 record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("ISAMORE dependency-bridge-v7 digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"ISAMORE dependency-bridge-v7 mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_V7_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
