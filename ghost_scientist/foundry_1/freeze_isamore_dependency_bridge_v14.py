#!/usr/bin/env python3
"""Create or verify the partial kiddo-family source freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/isamore_dependency_bridge_v14_freeze.json"
RECORDS = (
    "results/isamore_dependency_bridge_v13_freeze.json",
    "phase124_isamore_kiddo_partial_family_bridge_audit.py",
    "results/phase124_isamore_kiddo_partial_family_bridge_audit.json",
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
            HERE
            / "results/phase124_isamore_kiddo_partial_family_bridge_audit.json"
        ).read_text()
    )
    if not (
        result["status"]
        == "ISAMORE_KIDDO_PARTIAL_FAMILY_AUTHENTICATED_NO_STOP_ADVANCE"
        and len(result["bridge"]["packages"]) == 3
        and result["bridge"]["record_count"] == 13
        and result["checks"]["kiddo_root_source_acquired"] is False
        and result["next_build_stop"]["package"] == "kiddo"
        and result["control_executed"] is False
    ):
        raise RuntimeError("partial kiddo-family evidence invalid")
    records = rows()
    payload = {
        "version": "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V14",
        "records": records,
        "records_sha256": digest(records),
        "classification": "PARTIAL_KIDDO_FAMILY_SOURCE_NO_STOP_ADVANCE",
        "phases": [124],
        "bridged_packages": 3,
        "source_records": 13,
        "prior_stop": "kiddo",
        "next_stop": "kiddo",
        "kiddo_root_source_acquired": False,
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
        payload["version"] != "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V14"
        or payload["phases"] != [124]
        or payload["bridged_packages"] != 3
        or payload["source_records"] != 13
        or payload["prior_stop"] != "kiddo"
        or payload["next_stop"] != "kiddo"
        or payload["kiddo_root_source_acquired"] is not False
        or payload["control_executed"] is not False
        or payload["prospective_trial_authorized"] is not False
    ):
        raise RuntimeError("partial kiddo-family freeze changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("partial kiddo-family freeze digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"partial kiddo freeze mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_V14_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
