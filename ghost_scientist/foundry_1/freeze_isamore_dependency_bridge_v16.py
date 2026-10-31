#!/usr/bin/env python3
"""Create or verify the exact divrem family source freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/isamore_dependency_bridge_v16_freeze.json"
RECORDS = (
    "results/isamore_dependency_bridge_v15_freeze.json",
    "phase126_isamore_divrem_family_bridge_audit.py",
    "results/phase126_isamore_divrem_family_bridge_audit.json",
    "external_controls/isamore/vendor/divrem-1.0.0/Cargo.toml",
    "external_controls/isamore/vendor/divrem-1.0.0/src/lib.rs",
    "external_controls/isamore/vendor/divrem-1.0.0/src/macros.rs",
    "external_controls/isamore/vendor/divrem-1.0.0/src/ceil.rs",
    "external_controls/isamore/vendor/divrem-1.0.0/src/euclid.rs",
    "external_controls/isamore/vendor/divrem-1.0.0/src/floor.rs",
    "external_controls/isamore/vendor/divrem-1.0.0/src/trunc.rs",
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
            / "results/phase126_isamore_divrem_family_bridge_audit.json"
        ).read_text()
    )
    if not (
        result["status"]
        == "ISAMORE_DIVREM_EXACT_TAG_AUTHENTICATED_NO_STOP_ADVANCE"
        and result["bridge"]["record_count"] == 7
        and result["checks"]["source_compilation_passed"] is True
        and result["accumulated_kiddo_family"]["packages_bridged"] == 4
        and result["next_build_stop"]["package"] == "kiddo"
        and result["control_executed"] is False
    ):
        raise RuntimeError("divrem-family evidence invalid")
    records = rows()
    payload = {
        "version": "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V16",
        "records": records,
        "records_sha256": digest(records),
        "classification": "EXACT_DIVREM_TAG_NO_ISAMORE_STOP_ADVANCE",
        "phases": [126],
        "bridged_package": "divrem 1.0.0",
        "source_records": 7,
        "accumulated_kiddo_family_packages": 4,
        "accumulated_kiddo_family_required": 8,
        "accumulated_kiddo_family_source_records": 20,
        "prior_stop": "kiddo",
        "next_stop": "kiddo",
        "independent_source_compilation_passed": True,
        "isamore_algorithm_compilation_reached": False,
        "isamore_algorithm_execution_reached": False,
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
        payload["version"] != "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V16"
        or payload["phases"] != [126]
        or payload["bridged_package"] != "divrem 1.0.0"
        or payload["source_records"] != 7
        or payload["accumulated_kiddo_family_packages"] != 4
        or payload["accumulated_kiddo_family_required"] != 8
        or payload["accumulated_kiddo_family_source_records"] != 20
        or payload["prior_stop"] != "kiddo"
        or payload["next_stop"] != "kiddo"
        or payload["independent_source_compilation_passed"] is not True
        or payload["isamore_algorithm_compilation_reached"] is not False
        or payload["control_executed"] is not False
        or payload["prospective_trial_authorized"] is not False
    ):
        raise RuntimeError("divrem-family freeze changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("divrem-family freeze digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"divrem-family freeze mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_V16_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
