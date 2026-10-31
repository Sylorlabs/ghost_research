#!/usr/bin/env python3
"""Create or verify the post-hoc Enumo proving-power diagnostic freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_enumo_metamorphic_result_v1 import verify as verify_failed_result


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/enumo_power_diagnostic_v1_freeze.json"
RECORDS = (
    "freeze_enumo_power_diagnostic_v1.py",
    "results/enumo_metamorphic_result_v1_freeze.json",
    "phase49_enumo_power_diagnostic.py",
    "phase50_enumo_power_resource_audit.py",
    "results/phase49_enumo_power_diagnostic.json",
    "results/phase50_enumo_power_resource_audit.json",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows() -> list[dict[str, str]]:
    return [{"path": path, "sha256": sha(HERE / path)} for path in RECORDS]


def digest(value: list[dict[str, str]]) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def create() -> dict:
    verify_failed_result()
    if MANIFEST.exists():
        raise RuntimeError("Enumo power diagnostic freeze already exists")
    result = json.loads(
        (HERE / "results/phase49_enumo_power_diagnostic.json").read_text()
    )
    if result["classification"] != "POST_HOC_AFTER_METAMORPHIC_FAILURE":
        raise RuntimeError("Enumo diagnostic classification is not post-hoc")
    records = rows()
    payload = {
        "version": "FOUNDRY_ENUMO_POWER_DIAGNOSTIC_FREEZE_V1",
        "records": records,
        "records_sha256": digest(records),
        "classification": "POST_HOC_AFTER_METAMORPHIC_FAILURE",
        "bounded_mutual_derivability": True,
        "retroactively_changes_frozen_failure": False,
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    return payload


def verify() -> dict:
    verify_failed_result()
    payload = json.loads(MANIFEST.read_text(encoding="utf-8"))
    expected = {
        "version": "FOUNDRY_ENUMO_POWER_DIAGNOSTIC_FREEZE_V1",
        "classification": "POST_HOC_AFTER_METAMORPHIC_FAILURE",
        "bounded_mutual_derivability": True,
        "retroactively_changes_frozen_failure": False,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("Enumo power diagnostic classification changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("Enumo power diagnostic record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("Enumo power diagnostic digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"Enumo power diagnostic mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ENUMO_POWER_DIAGNOSTIC_V1_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
