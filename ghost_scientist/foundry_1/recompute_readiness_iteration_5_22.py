#!/usr/bin/env python3
"""Recompute readiness after freezing the V08 measured-search endpoint."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_21.json"
    freeze_path = (
        RESULTS / "pareto_v08_search_distinction_result_v1_freeze.json"
    )
    prior = json.loads(prior_path.read_text())
    freeze = json.loads(freeze_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and prior["authorization"]["active_stop_conditions"] == 1
        and freeze["status"]
        == "V08_SEARCH_DISTINCTION_PREFLIGHT_CONFORMANCE_PASS"
        and freeze["terminal_native_dedup_stop"]
        == "PENDING_PREFROZEN_V08_MEASUREMENT"
        and freeze["V08_measurement_passed"] is False
        and freeze["native_duplicate_fact_preserved"] is True
        and freeze["P1_advanced"] is False
        and freeze["production_integrated_arms"] == 6
    ):
        raise RuntimeError("iteration 5.22 inputs changed")
    authorization = {
        **prior["authorization"],
        "active_stop_conditions": 0,
        "pending_trial_validity_measurements": 1,
        "prospective_trial_authorized": False,
    }
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_22",
        "prior_sha256": sha(prior_path),
        "v08_search_distinction_freeze_sha256": sha(freeze_path),
        "prerequisites": prior["prerequisites"],
        "progress": {
            **prior["progress"],
            "autonomous_typed_grammar_already_established": True,
            "duplicate_grammar_phase_required": False,
            "candidate_calibration_unique_nodes": 53,
            "fixed_calibration_unique_nodes": 51,
            "candidate_calibration_total_cost": 2234,
            "fixed_calibration_total_cost": 2616,
            "candidate_runtime_inventions_admitted": 0,
            "candidate_stock_decomposition_duplicates": 4,
            "V08_search_receipt_fields_frozen": 22,
            "V08_hostile_ledgers_rejected": 15,
            "V08_bootstrap_resamples_frozen": 10000,
            "V08_terminal_native_dedup_stop_reclassified":
            "PENDING_PREFROZEN_V08_MEASUREMENT",
            "V08_measurement_passed": False,
        },
        "authorization": authorization,
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "A new grammar-construction build would duplicate phases 55 and 64: "
            "the LLM-free forge already chooses ATen targets and argument "
            "boundaries with zero supplied forms, and its independently replayed "
            "calibration portfolio covers 53 nodes at cost 2,234 versus the "
            "fixed portfolio's 51 at 2,616. The surviving native-dedup issue is "
            "now addressed by a pre-heldout V08 addendum that freezes 22 raw "
            "search receipt fields, paired CPU and structural ledgers, a 5% "
            "point threshold, a positive paired-bootstrap lower bound, and "
            "15 hostile failures. Runtime novelty remains zero and V08 remains "
            "unmeasured. The prior terminal stop is therefore pending a frozen "
            "trial measurement rather than silently waived."
        ),
        "remaining_blockers": [
            "P1 still lacks the fourth executed source-faithful control",
            "the exact published kiddo 5.2.4 root source is absent",
            "az 1.3.0, fixed 1.30.0, and sorted-vec 0.8.10 exact source bytes remain absent",
            "native Coin-OR CBC and the pinned nightly remain absent",
            "the production arm matrix remains 6/10",
            "the frozen V08 search distinction remains unmeasured until a fully authorized trial",
        ],
        "remediation": {
            "required": True,
            "next_action": (
                "keep validation-v6 sealed; continue the independent A6/ISAMORE "
                "source-faithful route when exact transport becomes available, "
                "and pursue only faithful A1/A7/A8 arm implementations rather "
                "than duplicate grammar construction or wrapper shortcuts"
            ),
            "forbidden_shortcuts": [
                "do not call the synthetic V08 positive control a heldout result",
                "do not claim V08 passed before the four real paired receipts exist",
                "do not relabel stock compiler decompositions as runtime inventions",
                "do not omit calibration construction or fixed and stock total-cost reporting",
                "do not count pre-registration as P1 or arm integration progress",
                "do not open validation-v6 before full authorization",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_22.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_22"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " controls=3/4 integrated=6/10"
        " terminal_stops=0 pending_V08=1 prospective=false"
    )


if __name__ == "__main__":
    main()
