#!/usr/bin/env python3
"""Create or verify the remaining Kiddo math-source channel freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/isamore_dependency_bridge_v17_freeze.json"
RECORDS = (
    "results/isamore_dependency_bridge_v16_freeze.json",
    "phase127_isamore_remaining_math_source_channel_audit.py",
    "results/phase127_isamore_remaining_math_source_channel_audit.json",
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
            / "results/phase127_isamore_remaining_math_source_channel_audit.json"
        ).read_text()
    )
    if not (
        result["status"]
        == "ISAMORE_REMAINING_MATH_CHANNELS_AUDITED_NO_EXACT_SOURCE"
        and len(result["locked_identities"]) == 3
        and result["rejected_substitution"]["accepted"] is False
        and result["accumulated_kiddo_family"]["packages_bridged"] == 4
        and result["next_build_stop"]["package"] == "kiddo"
        and result["control_executed"] is False
    ):
        raise RuntimeError("remaining-math channel evidence invalid")
    records = rows()
    payload = {
        "version": "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V17",
        "records": records,
        "records_sha256": digest(records),
        "classification": "REMAINING_MATH_CHANNELS_AUDITED_NO_SOURCE",
        "phases": [127],
        "locked_packages_audited": 3,
        "packages_acquired": 0,
        "third_party_mirror_substituted": False,
        "accumulated_kiddo_family_packages": 4,
        "accumulated_kiddo_family_required": 8,
        "accumulated_kiddo_family_source_records": 20,
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
        payload["version"] == "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V17"
        and payload["phases"] == [127]
        and payload["locked_packages_audited"] == 3
        and payload["packages_acquired"] == 0
        and payload["third_party_mirror_substituted"] is False
        and payload["accumulated_kiddo_family_packages"] == 4
        and payload["accumulated_kiddo_family_required"] == 8
        and payload["accumulated_kiddo_family_source_records"] == 20
        and payload["prior_stop"] == "kiddo"
        and payload["next_stop"] == "kiddo"
        and payload["control_executed"] is False
        and payload["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("remaining-math channel freeze changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("remaining-math channel freeze digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"remaining-math freeze mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_V17_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
