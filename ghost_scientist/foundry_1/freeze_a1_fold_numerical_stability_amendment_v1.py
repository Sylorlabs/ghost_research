#!/usr/bin/env python3
"""Freeze the disclosed A1 numerical remediation before panel execution."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
AMENDMENT = (
    HERE
    / "arm_adapter_fixtures/A1_FOLD_NUMERICAL_STABILITY_AMENDMENT_V1.json"
)
RESULT = HERE / "results/a1_fold_numerical_stability_amendment_v1_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    amendment = json.loads(AMENDMENT.read_text())
    if amendment["pristine_preregistration"] is not False:
        raise RuntimeError("post-failure amendment must not claim pristine status")
    if any(
        sha(HERE / row["path"]) != row["sha256"]
        for row in amendment["provider_records"]
    ):
        raise RuntimeError("amendment provider hash mismatch")
    failed = amendment["trigger"]["preserved_failed_result"]
    if sha(HERE / failed["path"]) != failed["sha256"]:
        raise RuntimeError("preserved failure changed")
    payload = {
        "version": "FOUNDRY_A1_FOLD_NUMERICAL_STABILITY_AMENDMENT_FREEZE_V1",
        "classification": "FROZEN_POST_FAILURE_BEFORE_UNSEEN_PANEL_EXECUTION",
        "amendment_sha256": sha(AMENDMENT),
        "provider_records": amendment["provider_records"],
        "preserved_failed_result": failed,
        "replicates_per_target": amendment["unseen_panel"][
            "replicates_per_target"
        ],
        "total_replicates": amendment["unseen_panel"]["total_replicates"],
        "absolute_tolerance": amendment[
            "amended_synthetic_numerical_contract"
        ]["absolute_tolerance"],
        "relative_tolerance": amendment[
            "amended_synthetic_numerical_contract"
        ]["relative_tolerance"],
        "frozen_before_amended_runner_implementation_or_panel_execution": True,
        "pristine_preregistration": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_FREEZE_A1_NUMERICAL_STABILITY"
        f" amendment={payload['amendment_sha256']}"
        f" unseen={payload['total_replicates']}"
        " pristine=false"
    )


if __name__ == "__main__":
    main()
