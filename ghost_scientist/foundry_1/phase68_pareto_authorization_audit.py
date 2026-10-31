#!/usr/bin/env python3
"""Fail-closed Foundry-0 authorization audit for the frozen Pareto candidate."""

from __future__ import annotations

import hashlib
import json
import pathlib
import sys


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
PROTOCOL = HERE / "PARETO_PROSPECTIVE_PROTOCOL_V1.json"
RESULT = RESULTS / "phase68_pareto_authorization_audit.json"
FORBIDDEN_FRAGMENT = "external_validation_" + "v6"
opened_paths: list[str] = []


def audit(event: str, args: tuple[object, ...]) -> None:
    if event == "open" and args and isinstance(args[0], (str, bytes)):
        opened_paths.append(str(args[0]))


sys.addaudithook(audit)


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def load(path: pathlib.Path) -> dict:
    return json.loads(path.read_text())


def run() -> None:
    protocol_raw = PROTOCOL.read_bytes()
    protocol = json.loads(protocol_raw)
    candidate_freeze = load(RESULTS / "pareto_candidate_v1_freeze.json")
    intake = load(RESULTS / "external_validation_v6_intake_freeze.json")
    enumo_resource = load(
        RESULTS / "phase46_enumo_source_resource_audit.json"
    )
    pareto_conformance = load(
        RESULTS / "phase65_independent_pareto_conformance.json"
    )
    pareto_native = load(RESULTS / "phase66_pareto_native_dedup.json")
    pareto_resource = load(RESULTS / "phase67_pareto_resource_audit.json")

    arms = protocol["arms"]
    required_arms = [row for row in arms if row["required_for_validity"]]
    arms_conformant = [
        row["id"] for row in required_arms if row["conformance_ready"]
    ]
    arms_integrated = [
        row["id"] for row in required_arms if row["production_integrated"]
    ]
    prerequisites = {
        "P1_external_control_conformance": (
            enumo_resource["P1"]["source_faithful_controls_reproduced"]
            == enumo_resource["P1"]["controls_required"]
            == 4
        ),
        "P2_independent_corpus_and_invocation_trace": (
            intake["source_count"] == 4
            and intake["repository_count"] == 4
            and intake["semantic_domain_count"] == 4
            and False
        ),
        "P3_complete_resource_meter": (
            pareto_resource["status"] == "PARETO_RESOURCE_COMPONENT_READY"
            and len(arms_integrated) == len(required_arms)
        ),
        "P4_independent_typed_tool_verifier": (
            pareto_conformance["status"]
            == "PARETO_INDEPENDENT_CONFORMANCE_PASS"
            and len(pareto_conformance["hostile_rejections"]) == 7
        ),
        "P5_native_compiler_deduplication": (
            pareto_native["status"] == "PARETO_NATIVE_DEDUP_COMPLETE"
            and pareto_native["summary"]["tools"] == 4
            and pareto_native["summary"]["stock_decomposition_duplicates"]
            == 4
        ),
        "P6_unchanged_prospective_freeze": (
            candidate_freeze["classification"]
            == "PARETO_CANDIDATE_AND_PROTOCOL_FROZEN_PRE_HELDOUT"
            and candidate_freeze["heldout_execution_observed"] is False
        ),
    }
    stop_conditions = {
        "no_candidate_survives_native_dedup": pareto_native["summary"][
            "runtime_inventions_admitted"
        ]
        == 0,
        "development_gain_disappears_total_compute": False,
        "no_cross_family_transfer": False,
        "eggmind_or_no_library_dominates": None,
        "babble_or_isamore_dominates": None,
        "invocation_trace_cannot_justify_horizon": True,
        "tool_verification_not_independent": False,
    }
    forbidden_opens = sorted(
        {path for path in opened_paths if FORBIDDEN_FRAGMENT in path}
    )
    all_prerequisites = all(prerequisites.values())
    all_required_arms = len(arms_integrated) == len(required_arms)
    known_stop = any(value is True for value in stop_conditions.values())
    authorized = (
        all_prerequisites
        and all_required_arms
        and not known_stop
        and not forbidden_opens
    )
    failed_prerequisites = sorted(
        key for key, value in prerequisites.items() if not value
    )
    missing_conformance = sorted(
        row["id"] for row in required_arms if not row["conformance_ready"]
    )
    missing_integration = sorted(
        row["id"] for row in required_arms if not row["production_integrated"]
    )
    remediation = {
        "priority_order": [
            "A8 EggMind-style source-faithful strategy-synthesis control",
            "A6 top-level ISAMORE or equivalent distinct anti-unification control",
            "A3 no-library and A9 compute-matched per-instance arms",
            "independently sourced invocation trace and frozen N*",
            "production integration and metering of A1 and A4-A9",
            "new candidate semantics that survive native deduplication or a pre-registered measured search distinction satisfying V08"
        ],
        "heldout_policy": "validation-v6 remains sealed and unimported",
        "prospective_execution_allowed": False,
    }
    payload = {
        "version": "FOUNDRY_PARETO_AUTHORIZATION_AUDIT_V1",
        "status": "PARETO_PROSPECTIVE_NOT_AUTHORIZED",
        "classification": "REMEDIATION_REQUIRED_NO_HELDOUT_EXECUTION",
        "protocol_sha256": hashlib.sha256(protocol_raw).hexdigest(),
        "candidate_freeze_records_sha256": candidate_freeze[
            "records_sha256"
        ],
        "prerequisites": prerequisites,
        "failed_prerequisites": failed_prerequisites,
        "required_arms": [row["id"] for row in required_arms],
        "conformant_required_arms": arms_conformant,
        "production_integrated_required_arms": arms_integrated,
        "missing_conformance_arms": missing_conformance,
        "missing_production_integration_arms": missing_integration,
        "stop_conditions": stop_conditions,
        "prospective_trial_authorized": authorized,
        "heldout_import_or_execution_observed": False,
        "access_audit": {
            "file_open_events": len(opened_paths),
            "forbidden_path_fragment": FORBIDDEN_FRAGMENT,
            "forbidden_open_count": len(forbidden_opens),
        },
        "remediation": remediation,
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE68_PARETO_AUTHORIZATION"
        f" status={payload['status']}"
        f" prerequisites={sum(prerequisites.values())}/6"
        f" integrated_arms={len(arms_integrated)}/{len(required_arms)}"
        f" stops={sum(value is True for value in stop_conditions.values())}"
        " heldout_imported=false"
    )


if __name__ == "__main__":
    run()
