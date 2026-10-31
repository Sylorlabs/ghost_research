#!/usr/bin/env python3
"""Audit whether the external request trace supplies Foundry-0's N-star unit."""

from __future__ import annotations

import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "external_traces/HORIZON_UNIT_MAPPING_PROTOCOL_V1.json"
RESULT = HERE / "results/phase80_horizon_unit_mapping_audit.json"
DOSSIER = HERE.parent / "foundry_0/FOUNDRY_0_DOSSIER.md"
FALSIFICATION = HERE.parent / "foundry_0/FALSIFICATION_PROTOCOL.md"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def run() -> None:
    protocol = json.loads(PROTOCOL.read_text(encoding="utf-8"))
    dossier = DOSSIER.read_text(encoding="utf-8")
    falsification = FALSIFICATION.read_text(encoding="utf-8")
    trace = json.loads(
        (HERE / "results/phase78_offline_trace_replay.json").read_text()
    )
    intake = json.loads(
        (
            HERE / "results/external_validation_v6_intake_freeze.json"
        ).read_text()
    )
    aggregate = trace["stdlib_parser"]
    normative = {
        "N_is_chronological_workload_stream_length": (
            "chronological workload stream of length `N`" in dossier
        ),
        "executed_workload_time_uses_invocation_counts": (
            "executed workload time at externally sourced invocation counts"
            in dossier
        ),
        "primary_endpoint_at_external_N_star": (
            "At the externally justified stream horizon `N*`"
            in falsification
        ),
        "trace_q25_is_requests_per_model": (
            aggregate["N_star_reference"] == 3
            and aggregate["nonempty_model_identities"] == 86
        ),
        "heldout_intake_has_four_sources": (
            intake["source_count"]
            == intake["repository_count"]
            == intake["semantic_domain_count"]
            == 4
        ),
    }
    mappings = {
        "M1_request_q25_to_artifact_N": {
            "decision": "REJECT_UNIT_MISMATCH",
            "input_value": 3,
            "input_unit": "successful requests per model identity",
            "required_unit": "chronological artifact arrivals",
        },
        "M2_request_q25_to_execution_K": {
            "decision": "ACCEPT_AS_SECONDARY_EXECUTION_MULTIPLICITY",
            "value": 3,
            "unit": "successful executions charged per heldout artifact",
            "supplies_protocol_N_star": False,
        },
        "M3_model_identities_to_artifact_N": {
            "decision": "REJECT_CURRENT_HARNESS_CAPACITY",
            "candidate_value": 86,
            "external_unit": "distinct deployed model identities",
            "frozen_heldout_source_identities": 4,
            "capacity_proven": False,
        },
    }
    checks = {
        "protocol_frozen": protocol["frozen_before_unit_decision"],
        "all_normative_relations_bound": all(normative.values()),
        "M1_rejected": (
            mappings["M1_request_q25_to_artifact_N"]["decision"]
            == "REJECT_UNIT_MISMATCH"
        ),
        "M2_secondary_only": (
            mappings["M2_request_q25_to_execution_K"][
                "supplies_protocol_N_star"
            ]
            is False
        ),
        "M3_capacity_rejected": (
            mappings["M3_model_identities_to_artifact_N"][
                "capacity_proven"
            ]
            is False
        ),
        "validation_v6_source_runtime_graph_unread": (
            intake["validation_graphs_exported_or_inspected"] is False
            and intake["validation_runtime_executed"] is False
        ),
    }
    if not all(checks.values()):
        raise RuntimeError("horizon unit mapping audit failed")
    payload = {
        "version": "FOUNDRY_HORIZON_UNIT_MAPPING_AUDIT_V1",
        "status": "HORIZON_UNIT_MAPPING_REJECTED_CURRENT_PROTOCOL",
        "normative_relations": normative,
        "mappings": mappings,
        "checks": checks,
        "correction": {
            "phase76_N_equals_3_interpretation": (
                "Retain as a calibration sensitivity at K=3 executions per "
                "artifact, not as proof of the Foundry-0 artifact-stream N-star."
            ),
            "iteration_4_0_stop_condition_cleared": False,
            "current_active_stop_conditions": 2,
        },
        "P2": {
            "independent_graph_corpus_frozen": True,
            "independent_request_trace_frozen": True,
            "execution_multiplicity_K_star": 3,
            "artifact_stream_N_star_justified": False,
            "complete": False,
        },
        "remediation_routes": [
            "Source a trace of chronological compiled-artifact arrivals with invocation counts and an N-star within the heldout harness capacity.",
            "Prospectively expand the heldout artifact stream to the externally observed 86-identity horizon without importing current validation-v6 outcomes.",
            "Obtain evaluator approval for a pre-outcome two-axis estimand that separates artifact count N from execution multiplicity K."
        ],
        "validation_v6_manifest_accessed": True,
        "validation_v6_source_runtime_graph_or_outcome_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE80_HORIZON_UNIT_MAPPING"
        f" status={payload['status']}"
        " K_star=3 N_star=UNJUSTIFIED"
        " P2=false active_stops=2 prospective=false"
    )


if __name__ == "__main__":
    run()
