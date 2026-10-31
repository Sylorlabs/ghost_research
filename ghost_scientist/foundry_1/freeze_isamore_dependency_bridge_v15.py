#!/usr/bin/env python3
"""Create or verify the kiddo-root acquisition-boundary freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/isamore_dependency_bridge_v15_freeze.json"
RECORDS = (
    "results/isamore_dependency_bridge_v14_freeze.json",
    "phase125_isamore_kiddo_root_acquisition_channel_audit.py",
    "results/phase125_isamore_kiddo_root_acquisition_channel_audit.json",
    (
        "external_controls/isamore/upstream_evidence/"
        "kiddo-20560517/Cargo.toml"
    ),
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
            / "results/phase125_isamore_kiddo_root_acquisition_channel_audit.json"
        ).read_text()
    )
    if not (
        result["status"]
        == "ISAMORE_KIDDO_ROOT_AVAILABLE_CHANNELS_AUDITED_NO_SOURCE"
        and result["locked_root"]["version"] == "5.2.4"
        and result["official_repository_evidence"][
            "manifest_declared_version"
        ]
        == "5.2.1"
        and result["checks"]["kiddo_root_source_acquired"] is False
        and result["next_build_stop"]["package"] == "kiddo"
    ):
        raise RuntimeError("kiddo acquisition-boundary evidence invalid")
    records = rows()
    payload = {
        "version": "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V15",
        "records": records,
        "records_sha256": digest(records),
        "classification": "KIDDO_ROOT_ACQUISITION_BOUNDARY_NO_SOURCE",
        "phases": [125],
        "locked_root": "kiddo 5.2.4",
        "release_adjacent_manifest_version": "5.2.1",
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
        payload["version"] != "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V15"
        or payload["phases"] != [125]
        or payload["locked_root"] != "kiddo 5.2.4"
        or payload["release_adjacent_manifest_version"] != "5.2.1"
        or payload["prior_stop"] != "kiddo"
        or payload["next_stop"] != "kiddo"
        or payload["kiddo_root_source_acquired"] is not False
        or payload["control_executed"] is not False
        or payload["prospective_trial_authorized"] is not False
    ):
        raise RuntimeError("kiddo acquisition-boundary freeze changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("kiddo acquisition-boundary freeze digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"kiddo acquisition-boundary freeze mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_V15_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
