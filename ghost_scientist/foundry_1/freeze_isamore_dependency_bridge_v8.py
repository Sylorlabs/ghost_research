#!/usr/bin/env python3
"""Create or verify the three-root env_logger bridge freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/isamore_dependency_bridge_v8_freeze.json"
RECORDS = (
    "results/isamore_dependency_bridge_v7_freeze.json",
    "phase118_isamore_env_logger_roots_bridge_audit.py",
    "results/phase118_isamore_env_logger_roots_bridge_audit.json",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows() -> list[dict[str, str]]:
    return [{"path": p, "sha256": sha(HERE / p)} for p in RECORDS]


def digest(rows_: list[dict[str, str]]) -> str:
    raw = json.dumps(rows_, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def create() -> dict:
    result = json.loads(
        (
            HERE / "results/phase118_isamore_env_logger_roots_bridge_audit.json"
        ).read_text()
    )
    if not (
        result["status"] == "ISAMORE_ENV_LOGGER_ROOTS_ADVANCE_STOP"
        and result["bridge"]["record_count"] == 37
        and len(result["bridge"]["multi_version_aliases"]) == 3
        and result["next_build_stop"]["package"] == "graphviz-rust"
        and result["control_executed"] is False
    ):
        raise RuntimeError("env_logger roots bridge evidence invalid")
    records = rows()
    payload = {
        "version": "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V8",
        "records": records,
        "records_sha256": digest(records),
        "classification": "THREE_ENV_LOGGER_TAG_ROOTS_NO_CONTROL_EXECUTION",
        "phases": [118],
        "root_versions": 3,
        "official_tag_records": 37,
        "prior_stop": "env_logger",
        "next_stop": "graphviz-rust",
        "algorithm_compilation_reached": False,
        "algorithm_execution_reached": False,
        "control_executed": False,
        "P1_complete": False,
        "prospective_trial_authorized": False,
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text())
    if (
        payload["version"] != "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V8"
        or payload["phases"] != [118]
        or payload["root_versions"] != 3
        or payload["official_tag_records"] != 37
        or payload["prior_stop"] != "env_logger"
        or payload["next_stop"] != "graphviz-rust"
        or payload["control_executed"] is not False
        or payload["prospective_trial_authorized"] is not False
    ):
        raise RuntimeError("env_logger roots bridge freeze changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("env_logger roots bridge freeze digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"env_logger roots freeze mismatch: {row['path']}")
    result = json.loads(
        (
            HERE / "results/phase118_isamore_env_logger_roots_bridge_audit.json"
        ).read_text()
    )
    for row in result["bridge"]["official_tag_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"env_logger source mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_V8_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
