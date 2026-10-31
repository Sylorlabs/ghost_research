#!/usr/bin/env python3
"""Create or verify the official-tag indicatif-family bridge freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/isamore_dependency_bridge_v12_freeze.json"
RECORDS = (
    "results/isamore_dependency_bridge_v11_freeze.json",
    "phase122_isamore_indicatif_family_bridge_audit.py",
    "results/phase122_isamore_indicatif_family_bridge_audit.json",
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
            HERE / "results/phase122_isamore_indicatif_family_bridge_audit.json"
        ).read_text()
    )
    if not (
        result["status"] == "ISAMORE_INDICATIF_FAMILY_ADVANCES_STOP"
        and len(result["bridge"]["packages"]) == 4
        and result["bridge"]["record_count"] == 35
        and result["bridge"]["all_release_tags_resolved"] is True
        and result["next_build_stop"]["package"] == "kiddo"
        and result["control_executed"] is False
    ):
        raise RuntimeError("indicatif family evidence invalid")
    records = rows()
    payload = {
        "version": "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V12",
        "records": records,
        "records_sha256": digest(records),
        "classification": "EXACT_OFFICIAL_TAG_INDICATIF_FAMILY_ADVANCE",
        "phases": [122],
        "bridged_packages": 4,
        "source_records": 35,
        "prior_stop": "indicatif",
        "next_stop": "kiddo",
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
        payload["version"] != "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V12"
        or payload["phases"] != [122]
        or payload["bridged_packages"] != 4
        or payload["source_records"] != 35
        or payload["prior_stop"] != "indicatif"
        or payload["next_stop"] != "kiddo"
        or payload["control_executed"] is not False
        or payload["prospective_trial_authorized"] is not False
    ):
        raise RuntimeError("indicatif family freeze changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("indicatif family freeze digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"indicatif family freeze mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_V12_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
