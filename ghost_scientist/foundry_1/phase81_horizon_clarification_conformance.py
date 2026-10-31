#!/usr/bin/env python3
"""Run independent conformance over the pre-outcome horizon clarification."""

from __future__ import annotations

import json
import pathlib

from independent_horizon_clarification import audit


HERE = pathlib.Path(__file__).resolve().parent
RESULT = HERE / "results/phase81_horizon_clarification_conformance.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def run() -> None:
    independent = audit(
        (HERE / "PARETO_PROSPECTIVE_PROTOCOL_V1.json").read_bytes(),
        (HERE / "PARETO_HORIZON_CLARIFICATION_V1.json").read_bytes(),
        (
            HERE / "results/external_validation_v6_intake_freeze.json"
        ).read_bytes(),
        (HERE / "results/phase78_offline_trace_replay.json").read_bytes(),
        (
            HERE / "results/phase80_horizon_unit_mapping_audit.json"
        ).read_bytes(),
    )
    if independent["status"] != "HORIZON_CLARIFICATION_CONFORMANCE_PASS":
        raise RuntimeError("horizon clarification conformance failed")
    payload = {
        "version": "FOUNDRY_HORIZON_CLARIFICATION_CONFORMANCE_V1",
        "status": independent["status"],
        "independent": independent,
        "P2": {
            "independent_graph_corpus_frozen": True,
            "independent_invocation_trace_locally_frozen": True,
            "offline_trace_replay_passed": True,
            "artifact_and_invocation_units_separated": True,
            "primary_coordinates": independent["coordinates"],
            "complete": True,
        },
        "scientific_boundary": {
            "P2_is_a_preflight_prerequisite_not_a_trial_result": True,
            "no_scientific_gate_passed_by_this_phase": True,
            "no_heldout_outcome_observed": True,
            "remaining_prerequisites": ["P1", "P3"],
            "remaining_active_stop": (
                "no candidate tool survives native-compiler deduplication"
            ),
        },
        "validation_v6_manifest_accessed": True,
        "validation_v6_source_runtime_graph_or_outcome_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE81_HORIZON_CLARIFICATION"
        f" status={payload['status']}"
        f" checks={independent['checks_passed']}/"
        f"{independent['checks_total']}"
        " coordinates=4x3 P2=true prospective=false"
    )


if __name__ == "__main__":
    run()
