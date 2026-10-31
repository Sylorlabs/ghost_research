#!/usr/bin/env python3
"""Create or verify the pre-frozen Babble metamorphic result freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_babble_metamorphic_v1 import verify as verify_prefreeze


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/babble_metamorphic_result_v1_freeze.json"
RECORDS = (
    "freeze_babble_metamorphic_result_v1.py",
    "results/babble_metamorphic_v1_freeze.json",
    "phase44_babble_metamorphic_resource_audit.py",
    "results/phase43_babble_metamorphic_control.json",
    "results/phase44_babble_metamorphic_resource_audit.json",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows() -> list[dict[str, str]]:
    return [{"path": path, "sha256": sha(HERE / path)} for path in RECORDS]


def digest(value: list[dict[str, str]]) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def create() -> dict:
    verify_prefreeze()
    if MANIFEST.exists():
        raise RuntimeError("Babble metamorphic result freeze already exists")
    records = rows()
    payload = {
        "version": "FOUNDRY_BABBLE_METAMORPHIC_RESULT_FREEZE_V1",
        "records": records,
        "records_sha256": digest(records),
        "classification": "PRE_FROZEN_METAMORPHIC_SOURCE_CONTROL_PASS",
        "metamorphic_relation_passed": True,
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    return payload


def verify() -> dict:
    verify_prefreeze()
    payload = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if (
        payload["version"]
        != "FOUNDRY_BABBLE_METAMORPHIC_RESULT_FREEZE_V1"
        or payload["classification"]
        != "PRE_FROZEN_METAMORPHIC_SOURCE_CONTROL_PASS"
        or payload["metamorphic_relation_passed"] is not True
    ):
        raise RuntimeError("Babble metamorphic result classification changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("Babble metamorphic result record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("Babble metamorphic result digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"Babble metamorphic result mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_BABBLE_METAMORPHIC_RESULT_V1_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
