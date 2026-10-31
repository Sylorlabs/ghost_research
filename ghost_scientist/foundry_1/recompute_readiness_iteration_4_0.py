#!/usr/bin/env python3
"""Recompute readiness after external invocation-horizon remediation."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_pareto_remediation_v2 import verify as verify_remediation


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
PRIOR = RESULTS / "readiness_iteration_3_9.json"
OUTPUT = RESULTS / "readiness_iteration_4_0.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def run() -> None:
    freeze = verify_remediation()
    trace = json.loads(
        (RESULTS / "phase74_external_invocation_trace_audit.json").read_text()
    )
    replay = json.loads(
        (RESULTS / "phase75_external_trace_independent_replay.json").read_text()
    )
    sensitivity = json.loads(
        (RESULTS / "phase76_external_horizon_sensitivity.json").read_text()
    )
    if not (
        trace["status"] == "EXTERNAL_INVOCATION_HORIZON_COMPONENT_READY"
        and replay["status"] == "EXTERNAL_TRACE_INDEPENDENT_REPLAY_PASS"
        and sensitivity["status"] == "CALIBRATION_HORIZON_SENSITIVITY_PASS"
        and freeze["P2_complete"] is False
        and freeze["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("invocation-horizon readiness evidence invalid")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_4_0",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": sha(PRIOR),
        "remediation_freeze_sha256": sha(
            RESULTS / "pareto_remediation_v2_freeze.json"
        ),
        "trace_audit_sha256": sha(
            RESULTS / "phase74_external_invocation_trace_audit.json"
        ),
        "trace_replay_sha256": sha(
            RESULTS / "phase75_external_trace_independent_replay.json"
        ),
        "horizon_sensitivity_sha256": sha(
            RESULTS / "phase76_external_horizon_sensitivity.json"
        ),
        "progress": {
            "independent_production_invocation_trace": True,
            "production_trace_rows": trace["trace"]["rows"],
            "production_model_identities": trace["trace"]["models"],
            "external_N_star_reference": trace["N_star_external_reference"],
            "independent_replay_relations_passed": replay[
                "exact_relations_passed"
            ],
            "calibration_cost_at_N_star": sensitivity["primary"][
                "candidate_cost"
            ],
            "fixed_cost_at_N_star": sensitivity["primary"]["fixed_cost"],
            "invocation_horizon_stop_condition_cleared": True,
            "P2_complete": False,
            "heldout_source_runtime_or_graph_accessed": False,
        },
        "prerequisites": {
            "P1_external_control_conformance": False,
            "P2_independent_corpus_and_invocation_trace": False,
            "P3_complete_resource_meter": False,
            "P4_independent_typed_tool_verifier": True,
            "P5_native_compiler_deduplication": True,
            "P6_unchanged_prospective_freeze": True,
        },
        "authorization": {
            "prerequisites_passed": 3,
            "prerequisites_required": 6,
            "required_arms_production_integrated": 2,
            "required_arms": 10,
            "active_stop_conditions": 1,
            "prospective_trial_authorized": False,
        },
        "remaining_blockers": [
            "exact production trace bytes are pinned by Git blob but not locally frozen for offline replay",
            "Stable Diffusion per-model demand has no pre-registered mapping to Foundry per-artifact heldout reuse",
            "A8 remains only a paper-derived partial boundary, not a full strategy-synthesis control",
            "A1 and A3-A9 are not all integrated behind one frozen prospective runner",
            "A4-A8 do not all have complete process-tree prospective resource paths",
            "zero candidate runtime inventions survive native deduplication",
        ],
        "remediation": {
            "next_action": (
                "freeze the exact licensed trace bytes for offline hashing and "
                "pre-register an evaluator-owned artifact-demand mapping; in "
                "parallel-independent work, define one arm adapter contract "
                "for A1 and A3-A9 without reading validation-v6"
            ),
            "required": True,
            "forbidden_shortcuts": [
                "do not treat connector aggregate receipts as locally frozen source bytes",
                "do not transfer Stable Diffusion demand to every compiler artifact by assertion",
                "do not treat calibration cost sensitivity as heldout victory",
                "do not open validation-v6 before a new authorization pass",
            ],
        },
        "interpretation": (
            "A real production request trace now supplies N-star=3 by a "
            "predeclared lower-quartile estimator, and an independent parser "
            "reproduces all 12 exact relations. At that deliberately small "
            "horizon the candidate's calibration accounting remains cheaper "
            "than fixed. This clears the narrow missing-horizon stop, but P2 "
            "remains false until the bytes and cross-domain mapping are "
            "prospectively reproducible."
        ),
    }
    OUTPUT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_READINESS_ITERATION_4_0"
        " verdict=FOUNDRY_V6_NOT_READY"
        " prerequisites=3/6"
        " integrated=2/10"
        " active_stops=1"
        " N_star=3 prospective=false"
    )


if __name__ == "__main__":
    run()
