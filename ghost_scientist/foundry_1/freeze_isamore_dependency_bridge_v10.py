#!/usr/bin/env python3
"""Create or verify the graphviz-family bridge freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/isamore_dependency_bridge_v10_freeze.json"
RECORDS = (
    "results/isamore_dependency_bridge_v9_freeze.json",
    "phase120_isamore_graphviz_family_bridge_audit.py",
    "results/phase120_isamore_graphviz_family_bridge_audit.json",
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
            HERE / "results/phase120_isamore_graphviz_family_bridge_audit.json"
        ).read_text()
    )
    if not (
        result["status"] == "ISAMORE_GRAPHVIZ_FAMILY_ADVANCES_STOP"
        and result["bridge"]["record_count"] == 16
        and len(result["bridge"]["packages"]) == 5
        and result["bridge"]["release_tag_resolved"] is False
        and result["next_build_stop"]["package"] == "indicatif"
        and result["control_executed"] is False
    ):
        raise RuntimeError("graphviz family bridge evidence invalid")
    records = rows()
    payload = {
        "version": "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V10",
        "records": records,
        "records_sha256": digest(records),
        "classification": "GRAPHVIZ_PINNED_MIXED_COMMIT_NO_CONTROL_EXECUTION",
        "phases": [120],
        "bridged_packages": 5,
        "source_records": 16,
        "prior_stop": "graphviz-rust",
        "next_stop": "indicatif",
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
        payload["version"] != "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V10"
        or payload["phases"] != [120]
        or payload["bridged_packages"] != 5
        or payload["source_records"] != 16
        or payload["prior_stop"] != "graphviz-rust"
        or payload["next_stop"] != "indicatif"
        or payload["control_executed"] is not False
        or payload["prospective_trial_authorized"] is not False
    ):
        raise RuntimeError("graphviz family bridge freeze changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("graphviz family bridge freeze digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"graphviz bridge freeze mismatch: {row['path']}")
    result = json.loads(
        (
            HERE / "results/phase120_isamore_graphviz_family_bridge_audit.json"
        ).read_text()
    )
    for row in result["bridge"]["source_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"graphviz source mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_V10_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
