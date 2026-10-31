#!/usr/bin/env python3
"""Create or verify the pre-heldout V08 search-distinction freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
GHOST = HERE.parent
PROTOCOL = HERE / "PARETO_V08_SEARCH_DISTINCTION_PROTOCOL_V1.json"
MANIFEST = HERE / "results/pareto_v08_search_distinction_v1_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate(protocol: dict[str, object]) -> None:
    for row in protocol["frozen_inputs"]:
        if sha(GHOST / row["path"]) != row["sha256"]:
            raise RuntimeError(f"V08 frozen input mismatch: {row['path']}")
    endpoint = protocol["primary_endpoint"]
    bootstrap = endpoint["paired_bootstrap"]
    hard = protocol["hard_acceptance"]
    preflight = protocol["preflight_effect"]
    claims = protocol["claim_boundary"]
    if not (
        protocol[
            "frozen_before_validation_v6_source_runtime_graph_or_outcome_access"
        ]
        is True
        and protocol["parent_contract"]["candidate_identity_changed"] is False
        and protocol["parent_contract"]["fixed_portfolio_changed"] is False
        and protocol["parent_contract"]["scientific_threshold_weakened"]
        is False
        and protocol["identity_boundary"]["primary_comparators"] == ["A3", "A9"]
        and protocol["identity_boundary"]["candidate_tools"] == 4
        and protocol["identity_boundary"][
            "candidate_runtime_inventions_admitted"
        ]
        == 0
        and protocol["measurement_schedule"]["artifacts"] == 4
        and protocol["measurement_schedule"]["invocations_per_artifact"] == 3
        and len(protocol["required_raw_receipt_fields"]) == 22
        and endpoint["point_estimate_minimum"] == 0.05
        and bootstrap["resamples"] == 10000
        and bootstrap["seed"] == 812734
        and bootstrap["lower_bound_must_be_strictly_positive"] is True
        and all(hard.values())
        and preflight["native_duplicate_fact_removed"] is False
        and preflight["V08_measurement_passed_before_heldout"] is False
        and preflight["known_terminal_native_dedup_stop_reclassified"]
        == "PENDING_PREFROZEN_V08_MEASUREMENT"
        and preflight["prospective_trial_authorized_by_this_protocol"] is False
        and claims["heldout_result_claimed"] is False
        and claims["V08_pass_claimed"] is False
        and claims["runtime_novelty_claimed"] is False
        and claims[
            "validation_v6_source_runtime_graph_or_outcome_accessed"
        ]
        is False
    ):
        raise RuntimeError("V08 search-distinction protocol invalid")


def create() -> dict[str, object]:
    protocol = json.loads(PROTOCOL.read_text())
    validate(protocol)
    return {
        "version": "FOUNDRY_PARETO_V08_SEARCH_DISTINCTION_FREEZE_V1",
        "protocol_sha256": sha(PROTOCOL),
        "frozen_inputs": protocol["frozen_inputs"],
        "frozen_before_heldout_execution": True,
        "candidate_tools": 4,
        "runtime_inventions_admitted": 0,
        "stock_decomposition_duplicates": 4,
        "primary_comparators": ["A3", "A9"],
        "artifacts": 4,
        "invocations_per_artifact": 3,
        "point_estimate_minimum": 0.05,
        "bootstrap_resamples": 10000,
        "bootstrap_seed": 812734,
        "required_raw_receipt_fields": 22,
        "terminal_native_dedup_stop_reclassified":
        "PENDING_PREFROZEN_V08_MEASUREMENT",
        "V08_measurement_passed": False,
        "runtime_novelty_claimed": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }


def verify() -> dict[str, object]:
    protocol = json.loads(PROTOCOL.read_text())
    validate(protocol)
    payload = json.loads(MANIFEST.read_text())
    if not (
        payload["version"]
        == "FOUNDRY_PARETO_V08_SEARCH_DISTINCTION_FREEZE_V1"
        and payload["protocol_sha256"] == sha(PROTOCOL)
        and payload["frozen_inputs"] == protocol["frozen_inputs"]
        and payload["frozen_before_heldout_execution"] is True
        and payload["candidate_tools"] == 4
        and payload["runtime_inventions_admitted"] == 0
        and payload["stock_decomposition_duplicates"] == 4
        and payload["primary_comparators"] == ["A3", "A9"]
        and payload["artifacts"] == 4
        and payload["invocations_per_artifact"] == 3
        and payload["point_estimate_minimum"] == 0.05
        and payload["bootstrap_resamples"] == 10000
        and payload["bootstrap_seed"] == 812734
        and payload["required_raw_receipt_fields"] == 22
        and payload["terminal_native_dedup_stop_reclassified"]
        == "PENDING_PREFROZEN_V08_MEASUREMENT"
        and payload["V08_measurement_passed"] is False
        and payload["runtime_novelty_claimed"] is False
        and payload["validation_v6_accessed"] is False
        and payload["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("V08 search-distinction freeze changed")
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
        "FOUNDRY_PARETO_V08_SEARCH_DISTINCTION_FREEZE_PASS"
        f" fields={payload['required_raw_receipt_fields']}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
