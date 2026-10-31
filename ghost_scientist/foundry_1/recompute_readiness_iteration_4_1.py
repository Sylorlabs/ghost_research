#!/usr/bin/env python3
"""Recompute readiness after offline P2 closure and horizon clarification."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_pareto_remediation_v3 import verify as verify_remediation


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
PRIOR = RESULTS / "readiness_iteration_4_0.json"
OUTPUT = RESULTS / "readiness_iteration_4_1.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def run() -> None:
    freeze = verify_remediation()
    provenance = json.loads(
        (RESULTS / "phase77_local_trace_provenance.json").read_text()
    )
    offline = json.loads(
        (RESULTS / "phase78_offline_trace_replay.json").read_text()
    )
    unit = json.loads(
        (RESULTS / "phase80_horizon_unit_mapping_audit.json").read_text()
    )
    clarification = json.loads(
        (
            RESULTS / "phase81_horizon_clarification_conformance.json"
        ).read_text()
    )
    resources = json.loads(
        (RESULTS / "phase82_horizon_protocol_resource_audit.json").read_text()
    )
    if not (
        provenance["status"] == "LOCAL_TRACE_BYTES_AUTHENTICATED"
        and offline["status"] == "OFFLINE_TRACE_REPLAY_PASS"
        and unit["status"]
        == "HORIZON_UNIT_MAPPING_REJECTED_CURRENT_PROTOCOL"
        and clarification["status"]
        == "HORIZON_CLARIFICATION_CONFORMANCE_PASS"
        and clarification["P2"]["complete"] is True
        and resources["status"] == "HORIZON_PROTOCOL_RESOURCE_PASS"
        and resources["P3"]["complete"] is False
        and freeze["P2_complete"] is True
        and freeze["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("readiness 4.1 evidence invalid")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_4_1",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": sha(PRIOR),
        "remediation_freeze_sha256": sha(
            RESULTS / "pareto_remediation_v3_freeze.json"
        ),
        "progress": {
            "P2_complete": True,
            "exact_trace_git_blobs": len(provenance["records"]),
            "exact_trace_bytes": provenance["records"][2]["bytes"],
            "offline_parsers": 2,
            "production_trace_rows": offline["stdlib_parser"]["data_rows"],
            "production_model_identities": offline["stdlib_parser"][
                "nonempty_model_identities"
            ],
            "artifact_coordinate": clarification["P2"][
                "primary_coordinates"
            ]["artifacts"],
            "invocations_per_artifact": clarification["P2"][
                "primary_coordinates"
            ]["invocations_per_artifact"],
            "execution_events": clarification["P2"][
                "primary_coordinates"
            ]["execution_events"],
            "bootstrap_pairing_unit": clarification["P2"][
                "primary_coordinates"
            ]["pairing_unit"],
            "unit_mismatch_preserved": True,
            "independent_no_weakening_checks": clarification["independent"][
                "checks_passed"
            ],
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
            "required_arms_production_integrated": 2,
            "required_arms": 10,
            "active_stop_conditions": 1,
            "prospective_trial_authorized": False,
        },
        "remaining_blockers": [
            "the fourth complete source-faithful control is still absent, so P1 fails",
            "A1 and A3-A9 are not all integrated and process-tree metered in one prospective runner, so P3 fails",
            "zero candidate runtime inventions survive native deduplication and the measured search distinction is not yet pre-registered in the final arm protocol",
            "only two of ten required arms are production-integrated",
        ],
        "remediation": {
            "next_action": (
                "define and independently verify one evaluator-owned arm "
                "adapter contract, integrate A1 and A3-A9 without opening "
                "validation-v6, and meter every adapter path; continue the "
                "fourth-control acquisition separately"
            ),
            "required": True,
            "forbidden_shortcuts": [
                "do not relabel three requests as three artifacts",
                "do not bootstrap 12 execution events as 12 independent samples",
                "do not count protocol-audit metering as complete arm metering",
                "do not call a stock-decomposition duplicate a runtime invention",
                "do not open validation-v6 before a new authorization pass",
            ],
        },
        "interpretation": (
            "P2 now closes as a preflight prerequisite, not a trial result. "
            "The four-artifact corpus and exact production trace are locally "
            "frozen; two offline parsers reproduce the trace; and an "
            "independent 18-check audit binds three executions per artifact "
            "without pseudoreplication or gate weakening. P1 and P3 still "
            "fail, only two arms are integrated, and native dedup leaves one "
            "active stop, so heldout execution remains forbidden."
        ),
    }
    OUTPUT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_READINESS_ITERATION_4_1"
        " verdict=FOUNDRY_V6_NOT_READY"
        " prerequisites=4/6"
        " integrated=2/10"
        " active_stops=1"
        " coordinates=4x3 prospective=false"
    )


if __name__ == "__main__":
    run()
