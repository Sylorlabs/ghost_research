#!/usr/bin/env python3
"""Create or verify the immutable Enumo tensor feasibility result freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULT = HERE / "results/phase132_enumo_tensor_domain_feasibility.json"
MANIFEST = HERE / "results/enumo_tensor_feasibility_result_v1_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def expected_records(result: dict[str, object]) -> list[dict[str, str]]:
    paths = [
        "arm_adapter_fixtures/ENUMO_TENSOR_DOMAIN_FEASIBILITY_PROTOCOL_V1.json",
        "results/enumo_tensor_feasibility_v1_freeze.json",
        "external_controls/enumo/tensor_feasibility/Cargo.toml",
        "external_controls/enumo/tensor_feasibility/Cargo.lock",
        "external_controls/enumo/tensor_feasibility/src/main.rs",
        "enumo_tensor_rule_verifier.py",
        "phase132_enumo_tensor_domain_feasibility.py",
    ]
    records = [
        {"path": path, "sha256": sha(HERE / path)}
        for path in paths
    ]
    runner = result["runner_records"]
    if not isinstance(runner, list):
        raise RuntimeError("runner records malformed")
    for row in runner:
        if row not in records:
            raise RuntimeError(f"result runner record not exact: {row}")
    return records


def create() -> dict[str, object]:
    result = json.loads(RESULT.read_text())
    if not (
        result["status"] == "ENUMO_TENSOR_DOMAIN_FEASIBILITY_PASS"
        and all(result["checks"].values())
        and result["observed"]["workload_counts"] == [38, 136]
        and result["observed"]["stage_rule_counts"] == [11, 7]
        and len(result["observed"]["learned_rules"]) == 18
        and result["independent_expanded_validation"]["rules_checked"] == 18
        and result["independent_expanded_validation"]["all_rules_passed"] is True
        and result["claim_boundary"]["is_frozen_boolean_A7"] is False
        and result["claim_boundary"]["A7_production_integrated"] is False
        and result["claim_boundary"]["production_integrated_arms"] == 6
        and result["claim_boundary"]["validation_v6_accessed"] is False
    ):
        raise RuntimeError("phase132 is not a passing bounded feasibility result")
    return {
        "version": "FOUNDRY_ENUMO_TENSOR_FEASIBILITY_RESULT_FREEZE_V1",
        "result_sha256": sha(RESULT),
        "records": expected_records(result),
        "status": result["status"],
        "learned_rule_count": len(result["observed"]["learned_rules"]),
        "independent_lane_checks": result[
            "independent_expanded_validation"
        ]["total_lane_checks"],
        "is_frozen_boolean_A7": False,
        "A7_production_integrated": False,
        "production_integrated_arms": 6,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }


def verify() -> dict[str, object]:
    payload = json.loads(MANIFEST.read_text())
    result = json.loads(RESULT.read_text())
    if not (
        payload["version"]
        == "FOUNDRY_ENUMO_TENSOR_FEASIBILITY_RESULT_FREEZE_V1"
        and payload["result_sha256"] == sha(RESULT)
        and payload["records"] == expected_records(result)
        and payload["status"] == "ENUMO_TENSOR_DOMAIN_FEASIBILITY_PASS"
        and payload["learned_rule_count"] == 18
        and payload["independent_lane_checks"] == 1176
        and payload["is_frozen_boolean_A7"] is False
        and payload["A7_production_integrated"] is False
        and payload["production_integrated_arms"] == 6
        and payload["validation_v6_accessed"] is False
        and payload["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("Enumo tensor feasibility result freeze changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"frozen result record mismatch: {row['path']}")
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
        "FOUNDRY_ENUMO_TENSOR_FEASIBILITY_RESULT_V1_FREEZE_PASS"
        f" rules={payload['learned_rule_count']}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
