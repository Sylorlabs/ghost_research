#!/usr/bin/env python3
"""Create or verify the EggMind reproduction-sufficiency result freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULT = (
    HERE
    / "results/phase135_eggmind_full_reproduction_sufficiency_audit.json"
)
MANIFEST = (
    HERE
    / "results/eggmind_reproduction_sufficiency_result_v1_freeze.json"
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def expected_records(result: dict[str, object]) -> list[dict[str, str]]:
    records = result["provider_records"]
    if not isinstance(records, list):
        raise RuntimeError("EggMind provider records malformed")
    local = [
        {
            "path": "phase135_eggmind_full_reproduction_sufficiency_audit.py",
            "sha256": sha(
                HERE
                / "phase135_eggmind_full_reproduction_sufficiency_audit.py"
            ),
        }
    ]
    return [*records, *local]


def create() -> dict[str, object]:
    result = json.loads(RESULT.read_text())
    if not (
        result["status"]
        == "EGGMIND_PAPER_ONLY_FULL_REPRODUCTION_NOT_SPECIFIED"
        and all(result["checks"].values())
        and result["surface_counts"]
        == {"specified": 10, "missing_outcome_determining": 16}
        and result["decisions"]["A8_production_integrated"] is False
        and result["decisions"]["P1_complete"] is False
        and result["validation_v6_accessed"] is False
    ):
        raise RuntimeError("phase135 is not the expected fail-closed result")
    return {
        "version":
        "FOUNDRY_EGGMIND_REPRODUCTION_SUFFICIENCY_RESULT_FREEZE_V1",
        "result_sha256": sha(RESULT),
        "records": expected_records(result),
        "status": result["status"],
        "specified_surfaces": 10,
        "missing_outcome_determining_surfaces": 16,
        "A8_production_integrated": False,
        "P1_complete": False,
        "production_integrated_arms": 6,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }


def verify() -> dict[str, object]:
    result = json.loads(RESULT.read_text())
    payload = json.loads(MANIFEST.read_text())
    if not (
        payload["version"]
        == "FOUNDRY_EGGMIND_REPRODUCTION_SUFFICIENCY_RESULT_FREEZE_V1"
        and payload["result_sha256"] == sha(RESULT)
        and payload["records"] == expected_records(result)
        and payload["status"]
        == "EGGMIND_PAPER_ONLY_FULL_REPRODUCTION_NOT_SPECIFIED"
        and payload["specified_surfaces"] == 10
        and payload["missing_outcome_determining_surfaces"] == 16
        and payload["A8_production_integrated"] is False
        and payload["P1_complete"] is False
        and payload["production_integrated_arms"] == 6
        and payload["validation_v6_accessed"] is False
        and payload["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("EggMind sufficiency result freeze changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(
                f"EggMind frozen provider mismatch: {row['path']}"
            )
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    if not existed:
        MANIFEST.write_text(
            json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
        )
    verify()
    print(
        "FOUNDRY_EGGMIND_REPRODUCTION_SUFFICIENCY_RESULT_V1_FREEZE_PASS"
        f" mode={'VERIFY' if existed else 'CREATE'}"
        " A8=false P1=false"
    )


if __name__ == "__main__":
    main()
