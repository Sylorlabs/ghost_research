#!/usr/bin/env python3
"""Create or verify the frozen prospective diversity result."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/diversity_result_v1_freeze.json"
RECORDS = (
    "freeze_diversity_result_v1.py",
    "results/diversity_candidate_v1_freeze.json",
    "results/phase59_prospective_diversity_trial.json",
    "results/phase60_prospective_diversity_resource_audit.json",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows() -> list[dict[str, str]]:
    return [{"path": path, "sha256": sha(HERE / path)} for path in RECORDS]


def digest(value: list[dict[str, str]]) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def create() -> dict:
    if MANIFEST.exists():
        raise RuntimeError("diversity result freeze already exists")
    trial = json.loads(
        (HERE / "results/phase59_prospective_diversity_trial.json").read_text()
    )
    resource = json.loads(
        (
            HERE
            / "results/phase60_prospective_diversity_resource_audit.json"
        ).read_text()
    )
    if (
        trial["status"] != "DIVERSITY_PROSPECTIVE_VALID_NEGATIVE"
        or resource["status"] != "PROSPECTIVE_DIVERSITY_RESOURCE_PASS"
    ):
        raise RuntimeError("unexpected prospective diversity result")
    records = rows()
    payload = {
        "version": "FOUNDRY_DIVERSITY_RESULT_FREEZE_V1",
        "records": records,
        "records_sha256": digest(records),
        "classification": "PROSPECTIVE_VALID_NEGATIVE",
        "exported_graphs": trial["exported_graphs"],
        "candidate_matched_tools": trial["candidate"]["matched_tools"],
        "candidate_matched_families": trial["candidate"]["matched_families"],
        "candidate_unique_node_benefit": trial["candidate"][
            "unique_node_benefit"
        ],
        "fixed_unique_node_benefit": trial["fixed"]["unique_node_benefit"],
        "candidate_total_cost": trial["candidate"]["total_cost"],
        "fixed_total_cost": trial["fixed"]["total_cost"],
        "candidate_only_families": len(trial["candidate_only_families"]),
        "resource_receipt_complete": resource["receipt_complete"],
        "posthoc_reclassification_allowed": False,
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text())
    expected = {
        "version": "FOUNDRY_DIVERSITY_RESULT_FREEZE_V1",
        "classification": "PROSPECTIVE_VALID_NEGATIVE",
        "exported_graphs": 4,
        "candidate_matched_tools": 2,
        "candidate_matched_families": 3,
        "candidate_unique_node_benefit": 11,
        "fixed_unique_node_benefit": 13,
        "candidate_total_cost": 294,
        "fixed_total_cost": 244,
        "candidate_only_families": 0,
        "resource_receipt_complete": True,
        "posthoc_reclassification_allowed": False,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("diversity prospective result changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("diversity result record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("diversity result record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"diversity result mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_DIVERSITY_RESULT_V1_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
