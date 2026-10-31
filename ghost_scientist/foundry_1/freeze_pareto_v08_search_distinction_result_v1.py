#!/usr/bin/env python3
"""Create or verify the immutable V08 preflight conformance result."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULT = HERE / "results/phase134_v08_search_distinction_conformance.json"
MANIFEST = (
    HERE / "results/pareto_v08_search_distinction_result_v1_freeze.json"
)
RECORDS = (
    "PARETO_V08_SEARCH_DISTINCTION_PROTOCOL_V1.json",
    "freeze_pareto_v08_search_distinction_v1.py",
    "results/pareto_v08_search_distinction_v1_freeze.json",
    "independent_v08_search_distinction.py",
    "phase134_v08_search_distinction_conformance.py",
    "results/phase134_v08_search_distinction_conformance.json",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def records() -> list[dict[str, str]]:
    return [
        {"path": path, "sha256": sha(HERE / path)}
        for path in RECORDS
    ]


def create() -> dict[str, object]:
    result = json.loads(RESULT.read_text())
    if not (
        result["status"]
        == "V08_SEARCH_DISTINCTION_PREFLIGHT_CONFORMANCE_PASS"
        and all(result["checks"].values())
        and all(result["worker"]["checks"].values())
        and result["worker"]["hostile_selftest"]["hostile_cases"] == 15
        and result["worker"]["hostile_selftest"]["rejected_cases"] == 15
        and result["worker"]["synthetic_positive_control"]["artifacts"] == 4
        and result["worker"]["synthetic_positive_control"]["receipts"] == 12
        and result["worker"]["synthetic_positive_control"][
            "bootstrap_resamples"
        ]
        == 10000
        and result["preflight_effect"]["duplicate_grammar_phase_required"]
        is False
        and result["preflight_effect"]["native_duplicate_fact_preserved"]
        is True
        and result["preflight_effect"]["terminal_native_dedup_stop"]
        == "PENDING_PREFROZEN_V08_MEASUREMENT"
        and result["preflight_effect"]["V08_measurement_passed"] is False
        and result["preflight_effect"]["P1_advanced"] is False
        and result["preflight_effect"]["production_integrated_arms"] == 6
        and result["preflight_effect"]["validation_v6_accessed"] is False
        and result["preflight_effect"]["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("phase134 is not the expected V08 preflight result")
    return {
        "version": "FOUNDRY_PARETO_V08_SEARCH_DISTINCTION_RESULT_FREEZE_V1",
        "result_sha256": sha(RESULT),
        "records": records(),
        "status": result["status"],
        "required_raw_receipt_fields": 22,
        "hostile_ledgers_rejected": 15,
        "bootstrap_resamples": 10000,
        "terminal_native_dedup_stop": "PENDING_PREFROZEN_V08_MEASUREMENT",
        "V08_measurement_passed": False,
        "native_duplicate_fact_preserved": True,
        "duplicate_grammar_phase_required": False,
        "P1_advanced": False,
        "production_integrated_arms": 6,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }


def verify() -> dict[str, object]:
    payload = json.loads(MANIFEST.read_text())
    if not (
        payload["version"]
        == "FOUNDRY_PARETO_V08_SEARCH_DISTINCTION_RESULT_FREEZE_V1"
        and payload["result_sha256"] == sha(RESULT)
        and payload["records"] == records()
        and payload["status"]
        == "V08_SEARCH_DISTINCTION_PREFLIGHT_CONFORMANCE_PASS"
        and payload["required_raw_receipt_fields"] == 22
        and payload["hostile_ledgers_rejected"] == 15
        and payload["bootstrap_resamples"] == 10000
        and payload["terminal_native_dedup_stop"]
        == "PENDING_PREFROZEN_V08_MEASUREMENT"
        and payload["V08_measurement_passed"] is False
        and payload["native_duplicate_fact_preserved"] is True
        and payload["duplicate_grammar_phase_required"] is False
        and payload["P1_advanced"] is False
        and payload["production_integrated_arms"] == 6
        and payload["validation_v6_accessed"] is False
        and payload["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("V08 preflight result freeze changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"V08 result record mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    if existed:
        payload = verify()
    else:
        payload = create()
        MANIFEST.write_text(
            json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
        )
    verify()
    print(
        "FOUNDRY_PARETO_V08_SEARCH_DISTINCTION_RESULT_FREEZE_PASS"
        f" hostile={payload['hostile_ledgers_rejected']}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
