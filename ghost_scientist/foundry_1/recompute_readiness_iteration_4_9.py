#!/usr/bin/env python3
"""Recompute readiness after complete A5 structural-control integration."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_pareto_remediation_v11 import verify as verify_remediation


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
PRIOR = RESULTS / "readiness_iteration_4_8.json"
OUTPUT = RESULTS / "readiness_iteration_4_9.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def main() -> None:
    freeze = verify_remediation()
    if not (
        freeze[
            "A5_production_integrated_calibration_structural_control"
        ]
        is True
        and freeze["production_integrated_arms"] == 6
        and freeze["P3_complete"] is False
        and freeze["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("readiness 4.9 evidence invalid")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_4_9",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": sha(PRIOR),
        "remediation_freeze_sha256": sha(
            RESULTS / "pareto_remediation_v11_freeze.json"
        ),
        "progress": {
            "P2_complete": True,
            "A1_compatibility_audited_not_integrated": True,
            "A3_A9_production_integrated_calibration_arms": True,
            "A4_production_integrated_calibration_arm": True,
            "A5_abstractions": 1,
            "A5_structural_rewrite_uses": 329,
            "A5_unabstracted_nonempty_kwargs_calls": 8,
            "A5_normalized_reconstructions": 23,
            "A5_raw_encoder_byte_reconstructions": 0,
            "A5_whole_graph_executions": 69,
            "A5_maximum_error": 0.0,
            "A5_base_contract_pairs_accepted": 23,
            "A5_shared_resource_receipts_charged": 1,
            "A5_hostile_batches_rejected_twice": 19,
            "A5_rewritten_tensor_runtime_executed": False,
            "A5_tensor_primitive_invented": False,
            "A5_heldout_generalization_measured": False,
            "A5_fixed_portfolio_beaten": False,
            "A5_production_integrated_calibration_structural_control": True,
            "production_integrated_arms": 6,
            "required_arms": 10,
            "P3_complete": False,
            "heldout_source_runtime_graph_or_outcome_accessed": False,
        },
        "prerequisites": {
            "P1_external_control_conformance": False,
            "P2_independent_corpus_and_invocation_trace": True,
            "P3_complete_resource_meter": False,
            "P4_independent_typed_tool_verifier": True,
            "P5_native_compiler_deduplication": True,
            "P6_unchanged_prospective_freeze": True,
        },
        "authorization": {
            "prerequisites_passed": 4,
            "prerequisites_required": 6,
            "required_arms_production_integrated": 6,
            "required_arms": 10,
            "active_stop_conditions": 1,
            "prospective_trial_authorized": False,
        },
        "remaining_blockers": [
            "P1 still lacks the fourth complete source-faithful control",
            "A1 remains incompatible with the complete framework IR and is not integrated",
            "A7 has not passed complete typed-graph compatibility, runtime, contract, and resource gates",
            "A6 and A8 remain required fail-closed arms with incomplete declared controls",
            "all ten required arm paths do not yet have explicit metered outcomes",
            "zero candidate runtime inventions survive native deduplication and the final measured-search distinction remains unregistered"
        ],
        "remediation": {
            "next_action": (
                "audit A7 rule inference against the complete typed graph "
                "surface before deciding whether faithful adaptation is "
                "possible; do not substitute Stitch or replay semantics"
            ),
            "required": True,
            "forbidden_shortcuts": [
                "do not call the empty-kwargs scaffold a tensor primitive",
                "do not treat normalized textual reconstruction as rewritten tensor execution",
                "do not claim held-out generalization, runtime benefit, or fixed-portfolio superiority for A5",
                "do not count incomplete or incompatible arms as integrated",
                "do not mount or execute validation-v6 before authorization"
            ]
        },
        "interpretation": (
            "A5 is now a complete production-integrated calibration "
            "structural control. Upstream Stitch reproducibly compresses the "
            "typed calibration encoding, but the only learned abstraction is "
            "the empty-kwargs call/sequence scaffold. Independent normalized "
            "reconstruction, framework parity, shared accounting, and hostile "
            "contract gates pass. This advances integrated truth to six of "
            "ten without claiming tensor invention, held-out transfer, speed, "
            "or superiority. P1 and P3 remain open."
        ),
    }
    OUTPUT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_READINESS_ITERATION_4_9"
        " verdict=FOUNDRY_V6_NOT_READY"
        " prerequisites=4/6 integrated=6/10"
        " A5=STRUCTURAL_PASS prospective=false"
    )


if __name__ == "__main__":
    main()
