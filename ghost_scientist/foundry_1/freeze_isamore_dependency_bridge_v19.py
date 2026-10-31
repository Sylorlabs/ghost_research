#!/usr/bin/env python3
"""Create or verify the native LP acquisition-channel freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/isamore_dependency_bridge_v19_freeze.json"
RECORDS = (
    "results/isamore_dependency_bridge_v18_freeze.json",
    "phase129_isamore_native_lp_acquisition_channel_audit.py",
    "results/phase129_isamore_native_lp_acquisition_channel_audit.json",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows() -> list[dict[str, str]]:
    return [{"path": path, "sha256": sha(HERE / path)} for path in RECORDS]


def digest(records: list[dict[str, str]]) -> str:
    raw = json.dumps(records, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def create() -> dict:
    result = json.loads(
        (
            HERE
            / "results/phase129_isamore_native_lp_acquisition_channel_audit.json"
        ).read_text()
    )
    if not (
        result["status"]
        == "ISAMORE_NATIVE_LP_CHANNELS_IDENTIFIED_TRANSPORT_UNAVAILABLE"
        and result["apt_channels"]["candidate_version"] == "2.10.11+ds1-2"
        and result["checks"]["native_cbc_download_succeeded"] is False
        and result["checks"]["system_package_install_attempted"] is False
        and result["checks"]["system_libcbc_available"] is False
        and result["checks"]["pinned_nightly_available"] is False
        and result["next_build_stop"]["package"] == "kiddo"
        and result["control_executed"] is False
    ):
        raise RuntimeError("native LP acquisition evidence invalid")
    records = rows()
    payload = {
        "version": "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V19",
        "records": records,
        "records_sha256": digest(records),
        "classification": "NATIVE_LP_CHANNELS_IDENTIFIED_TRANSPORT_UNAVAILABLE",
        "phases": [129],
        "apt_candidate_version": "2.10.11+ds1-2",
        "native_cbc_downloaded": False,
        "native_cbc_installed": False,
        "native_libcbc_available": False,
        "pinned_nightly_available": False,
        "link_attempted": False,
        "solver_executed": False,
        "prior_stop": "kiddo",
        "next_stop": "kiddo",
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
    if not (
        payload["version"] == "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V19"
        and payload["phases"] == [129]
        and payload["apt_candidate_version"] == "2.10.11+ds1-2"
        and payload["native_cbc_downloaded"] is False
        and payload["native_cbc_installed"] is False
        and payload["native_libcbc_available"] is False
        and payload["pinned_nightly_available"] is False
        and payload["link_attempted"] is False
        and payload["solver_executed"] is False
        and payload["prior_stop"] == "kiddo"
        and payload["next_stop"] == "kiddo"
        and payload["control_executed"] is False
        and payload["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("native LP acquisition freeze changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("native LP acquisition freeze digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"native LP freeze mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_V19_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
