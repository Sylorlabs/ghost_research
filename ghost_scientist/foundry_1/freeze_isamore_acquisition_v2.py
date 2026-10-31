#!/usr/bin/env python3
"""Create or verify the authenticated ISAMORE acquisition/build stop."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
SOURCE = HERE / "external_controls/isamore/source"
MANIFEST = HERE / "results/isamore_acquisition_v2_freeze.json"
RECORDS = (
    "phase111_isamore_recursive_source_acquisition.py",
    "results/phase111_isamore_recursive_source_acquisition.json",
    "phase112_isamore_offline_build_closure.py",
    "results/phase112_isamore_offline_build_closure.json",
    "external_controls/isamore/source/.cargo/config.toml",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_blob(path: pathlib.Path) -> str:
    raw = path.read_bytes()
    return hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()


def rows() -> list[dict[str, str]]:
    return [{"path": path, "sha256": sha(HERE / path)} for path in RECORDS]


def digest(value: list[dict[str, str]]) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def verify_source_records(acquisition: dict) -> None:
    for row in acquisition["source_records"]:
        path = SOURCE / row["path"]
        if (
            not path.is_file()
            or sha(path) != row["sha256"]
            or git_blob(path) != row["git_blob_sha1"]
            or path.stat().st_size != row["bytes"]
        ):
            raise RuntimeError(
                f"ISAMORE acquired source mismatch: {row['path']}"
            )


def create() -> dict:
    if MANIFEST.exists():
        raise RuntimeError("ISAMORE acquisition-v2 freeze already exists")
    acquisition = json.loads(
        (
            HERE / "results/phase111_isamore_recursive_source_acquisition.json"
        ).read_text()
    )
    build = json.loads(
        (HERE / "results/phase112_isamore_offline_build_closure.json").read_text()
    )
    verify_source_records(acquisition)
    if not (
        acquisition["status"]
        == "ISAMORE_SOURCE_ACQUISITION_COMPONENT_PASS"
        and acquisition["source_records_exact"] is True
        and acquisition["recursive_submodule_identities_observed"] is True
        and len(acquisition["submodule_gitlinks"]) == 4
        and acquisition["published_workload"]["present"] is True
        and acquisition["control_executed"] is False
        and build["status"]
        == "ISAMORE_BUILD_CLOSURE_AUTHENTICATED_STOP"
        and build["checks"]["offline_locked_metadata_resolved"] is True
        and build["checks"]["offline_locked_build_attempted"] is True
        and build["checks"][
            "first_missing_registry_package_authenticated"
        ]
        is True
        and build["checks"]["route_buildable"] is False
        and build["control_executed"] is False
        and build["P1_complete"] is False
        and build["validation_v6_accessed"] is False
    ):
        raise RuntimeError("ISAMORE acquisition-v2 evidence is invalid")
    records = rows()
    payload = {
        "version": "FOUNDRY_ISAMORE_ACQUISITION_FREEZE_V2",
        "records": records,
        "records_sha256": digest(records),
        "classification": (
            "AUTHENTICATED_RECURSIVE_SOURCE_AND_WORKLOAD_"
            "OFFLINE_BUILD_INFRASTRUCTURE_STOP"
        ),
        "phases": [111, 112],
        "source_record_count": acquisition["source_record_count"],
        "submodule_gitlinks_observed": 4,
        "published_workload_present": True,
        "offline_locked_metadata_resolved": True,
        "offline_locked_build_attempted": True,
        "first_missing_registry_package": "colored",
        "route_buildable": False,
        "control_executed": False,
        "source_faithful_controls_reproduced": 3,
        "controls_required": 4,
        "P1_complete": False,
        "prospective_trial_authorized": False,
        "validation_v6_accessed": False,
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text())
    fixed = {
        "version": "FOUNDRY_ISAMORE_ACQUISITION_FREEZE_V2",
        "classification": (
            "AUTHENTICATED_RECURSIVE_SOURCE_AND_WORKLOAD_"
            "OFFLINE_BUILD_INFRASTRUCTURE_STOP"
        ),
        "phases": [111, 112],
        "source_record_count": 29,
        "submodule_gitlinks_observed": 4,
        "published_workload_present": True,
        "offline_locked_metadata_resolved": True,
        "offline_locked_build_attempted": True,
        "first_missing_registry_package": "colored",
        "route_buildable": False,
        "control_executed": False,
        "source_faithful_controls_reproduced": 3,
        "controls_required": 4,
        "P1_complete": False,
        "prospective_trial_authorized": False,
        "validation_v6_accessed": False,
    }
    if any(payload[key] != value for key, value in fixed.items()):
        raise RuntimeError("ISAMORE acquisition-v2 freeze changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("ISAMORE acquisition-v2 record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("ISAMORE acquisition-v2 record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"ISAMORE acquisition-v2 mismatch: {row['path']}"
            )
    acquisition = json.loads(
        (
            HERE / "results/phase111_isamore_recursive_source_acquisition.json"
        ).read_text()
    )
    verify_source_records(acquisition)
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ISAMORE_ACQUISITION_V2_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
