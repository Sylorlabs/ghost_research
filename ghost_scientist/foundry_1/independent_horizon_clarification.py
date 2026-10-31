#!/usr/bin/env python3
"""Independent stdlib-only audit for the two-axis horizon clarification."""

from __future__ import annotations

import hashlib
import json
from typing import Any


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def audit(
    parent_raw: bytes,
    clarification_raw: bytes,
    intake_raw: bytes,
    offline_trace_raw: bytes,
    unit_audit_raw: bytes,
) -> dict[str, Any]:
    parent = json.loads(parent_raw)
    clarification = json.loads(clarification_raw)
    intake = json.loads(intake_raw)
    trace = json.loads(offline_trace_raw)
    unit = json.loads(unit_audit_raw)
    coordinates = clarification["primary_coordinates"]
    checks = {
        "parent_hash_exact": (
            hashlib.sha256(parent_raw).hexdigest()
            == clarification["parent_protocol_sha256"]
        ),
        "candidate_unchanged": parent["candidate"]["tools"] == 4,
        "heldout_identity_unchanged": (
            parent["heldout"]["source_freeze"]
            == "results/external_validation_v6_intake_freeze.json"
            and parent["heldout"]["families"] == 4
            and intake["source_count"]
            == intake["repository_count"]
            == intake["semantic_domain_count"]
            == 4
        ),
        "artifact_coordinate_exact": coordinates["A_star_artifacts"] == 4,
        "invocation_coordinate_exact": (
            coordinates["K_star_invocations_per_artifact"]
            == trace["stdlib_parser"]["N_star_reference"]
            == 3
        ),
        "event_product_exact": (
            coordinates["total_execution_events"]
            == coordinates["A_star_artifacts"]
            * coordinates["K_star_invocations_per_artifact"]
            == 12
        ),
        "artifact_is_pairing_unit": (
            coordinates["pairing_and_bootstrap_unit"] == "artifact"
            and coordinates["bootstrap_sample_size"] == 4
        ),
        "pseudoreplication_forbidden": (
            "never count as three independent artifacts"
            in coordinates["pseudoreplication_rule"]
        ),
        "phase76_demoted_to_secondary": clarification["claim_boundary"][
            "phase76_is_secondary_calibration_sensitivity_only"
        ],
        "unit_mismatch_preserved": (
            unit["mappings"]["M1_request_q25_to_artifact_N"]["decision"]
            == "REJECT_UNIT_MISMATCH"
            and clarification["claim_boundary"][
                "K_star_is_not_artifact_stream_length"
            ]
        ),
        "all_parent_arms_retained": (
            [row["id"] for row in parent["arms"]]
            == ["A0", "A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9", "A10"]
        ),
        "all_parent_hard_gates_retained": (
            len(parent["hard_validity_gates"]) == 12
        ),
        "all_parent_scientific_gates_retained": (
            len(parent["scientific_gates"]) == 12
        ),
        "all_parent_stop_conditions_retained": (
            len(parent["stop_conditions"]) == 7
        ),
        "point_threshold_retained": any(
            "at-least-5-percent point-estimate requirement" in value
            for value in clarification["unchanged_from_parent"]
        ),
        "confidence_threshold_retained": any(
            "positive lower 95-percent paired bootstrap confidence-bound requirement"
            in value
            for value in clarification["unchanged_from_parent"]
        ),
        "heldout_unobserved": (
            clarification["chronology"][
                "validation_v6_source_runtime_graph_or_outcome_accessed"
            ]
            is False
            and clarification["chronology"][
                "candidate_or_fixed_heldout_outcome_observed"
            ]
            is False
            and intake["validation_graphs_exported_or_inspected"] is False
            and intake["validation_runtime_executed"] is False
        ),
        "authorization_not_granted": (
            clarification["claim_boundary"][
                "prospective_trial_authorized_by_this_file"
            ]
            is False
        ),
    }
    return {
        "status": (
            "HORIZON_CLARIFICATION_CONFORMANCE_PASS"
            if all(checks.values())
            else "HORIZON_CLARIFICATION_CONFORMANCE_FAIL"
        ),
        "checks": checks,
        "checks_passed": sum(checks.values()),
        "checks_total": len(checks),
        "parent_protocol_sha256": hashlib.sha256(parent_raw).hexdigest(),
        "clarification_sha256": hashlib.sha256(
            clarification_raw
        ).hexdigest(),
        "coordinates": {
            "artifacts": coordinates["A_star_artifacts"],
            "invocations_per_artifact": coordinates[
                "K_star_invocations_per_artifact"
            ],
            "execution_events": coordinates["total_execution_events"],
            "pairing_unit": coordinates["pairing_and_bootstrap_unit"],
        },
    }
