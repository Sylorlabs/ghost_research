#!/usr/bin/env python3
"""Create or verify the post-prospective failure-calibration freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/diversity_failure_calibration_v1_freeze.json"
RECORDS = (
    "freeze_diversity_failure_calibration_v1.py",
    "phase61_diversity_failure_calibration.py",
    "phase62_diversity_failure_resource_audit.py",
    "results/diversity_result_v1_freeze.json",
    "results/phase61_diversity_failure_calibration.json",
    "results/phase62_diversity_failure_resource_audit.json",
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
        raise RuntimeError("diversity failure calibration freeze already exists")
    result = json.loads(
        (
            HERE / "results/phase61_diversity_failure_calibration.json"
        ).read_text()
    )
    resource = json.loads(
        (
            HERE / "results/phase62_diversity_failure_resource_audit.json"
        ).read_text()
    )
    if (
        result["status"] != "DIVERSITY_FAILURE_MECHANISM_AUDIT_COMPLETE"
        or result["classification"] != "POST_PROSPECTIVE_CALIBRATION_ONLY"
        or result["prospective_claim_allowed"] is not False
        or resource["status"] != "DIVERSITY_FAILURE_RESOURCE_PASS"
    ):
        raise RuntimeError("diversity failure calibration is incomplete")
    records = rows()
    payload = {
        "version": "FOUNDRY_DIVERSITY_FAILURE_CALIBRATION_FREEZE_V1",
        "records": records,
        "records_sha256": digest(records),
        "classification": "POST_PROSPECTIVE_CALIBRATION_ONLY",
        "failed_gates": len(result["failed_gates"]),
        "candidate_coverage_deficit": result["mechanisms"][
            "coverage_deficit"
        ]["deficit"],
        "discarded_machine_rediscovered_fixed_sequences": result[
            "mechanisms"
        ]["novelty_only_portfolio_constraint"][
            "machine_rediscovered_fixed_sequences_discarded"
        ],
        "equal_cohort_efficiency_break_even": result["mechanisms"][
            "upfront_search_amortization"
        ]["repeated_equal_cohort_efficiency_break_even"],
        "prospective_claim_allowed": False,
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text())
    expected = {
        "version": "FOUNDRY_DIVERSITY_FAILURE_CALIBRATION_FREEZE_V1",
        "classification": "POST_PROSPECTIVE_CALIBRATION_ONLY",
        "failed_gates": 4,
        "candidate_coverage_deficit": 2,
        "discarded_machine_rediscovered_fixed_sequences": 5,
        "equal_cohort_efficiency_break_even": 2,
        "prospective_claim_allowed": False,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("diversity failure calibration changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("failure calibration record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("failure calibration record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"failure calibration mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_DIVERSITY_FAILURE_CALIBRATION_V1_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
