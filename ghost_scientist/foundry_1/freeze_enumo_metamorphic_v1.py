#!/usr/bin/env python3
"""Create or verify the pre-execution Enumo metamorphic freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_enumo_source_result_v1 import verify as verify_baseline


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/enumo_metamorphic_v1_freeze.json"
RECORDS = (
    "freeze_enumo_metamorphic_v1.py",
    "external_controls/enumo/metamorphic_control/Cargo.toml",
    "external_controls/enumo/metamorphic_control/src/main.rs",
    "phase47_enumo_metamorphic_control.py",
    "results/enumo_source_result_v1_freeze.json",
    "results/phase45_enumo_source_control.json",
    "external_controls/enumo/control/Cargo.toml",
    "external_controls/enumo/control/Cargo.lock",
    "external_controls/enumo/egg_control/Cargo.toml",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows() -> list[dict[str, str]]:
    return [{"path": path, "sha256": sha(HERE / path)} for path in RECORDS]


def digest(value: list[dict[str, str]]) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def create() -> dict:
    verify_baseline()
    if MANIFEST.exists():
        raise RuntimeError("Enumo metamorphic freeze already exists")
    records = rows()
    payload = {
        "version": "FOUNDRY_ENUMO_METAMORPHIC_FREEZE_V1",
        "records": records,
        "records_sha256": digest(records),
        "boundary": {
            "baseline_outcome_observed": True,
            "metamorphic_outcome_observed": False,
            "exact_full_rule_set_relation_frozen": True,
            "published_variable_names_reused": False,
            "published_enumeration_order_reused": False,
            "algorithm_source_mutation_allowed": False,
        },
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    return payload


def verify() -> dict:
    verify_baseline()
    payload = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if payload["version"] != "FOUNDRY_ENUMO_METAMORPHIC_FREEZE_V1":
        raise RuntimeError("Enumo metamorphic freeze version changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("Enumo metamorphic record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("Enumo metamorphic record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"Enumo metamorphic mismatch: {row['path']}")
    expected = {
        "baseline_outcome_observed": True,
        "metamorphic_outcome_observed": False,
        "exact_full_rule_set_relation_frozen": True,
        "published_variable_names_reused": False,
        "published_enumeration_order_reused": False,
        "algorithm_source_mutation_allowed": False,
    }
    if payload["boundary"] != expected:
        raise RuntimeError("Enumo metamorphic boundary changed")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ENUMO_METAMORPHIC_V1_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
