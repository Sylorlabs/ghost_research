#!/usr/bin/env python3
"""Recompute readiness after the v7 intake privacy repair."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_31.json"
    audit_path = RESULTS / "phase156_validation_v7_identity_privacy_audit.json"
    freeze_path = RESULTS / "validation_v7_identity_only_intake_v2_freeze.json"
    intake_path = RESULTS / "phase157_validation_v7_identity_only_intake_v2.json"
    prior = json.loads(prior_path.read_text())
    audit = json.loads(audit_path.read_text())
    freeze = json.loads(freeze_path.read_text())
    intake = json.loads(intake_path.read_text())
    summary = intake["observed"]["summary"]
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and prior["progress"]["production_integrated_arms"] == 10
        and audit["status"]
        == "VALIDATION_V7_V1_PRIVACY_DEFECT_CONFIRMED_NO_REAL_EXPOSURE"
        and audit["decision"][
            "validation_v7_identity_intake_v1_allowed_for_real_bundle"
        ]
        is False
        and freeze["status"]
        == "FROZEN_BEFORE_V2_VALIDATORS_OR_EXTERNAL_BUNDLE"
        and intake["status"]
        == "VALIDATION_V7_IDENTITY_ONLY_INTAKE_V2_WAITING"
        and intake["operationally_valid"] is True
        and all(intake["checks"].values())
        and summary["positive_validators"] == 2
        and summary["hostile_cases"] == 18
        and summary["hostile_rejected_twice"] == 18
        and summary["real_present_required_files"] == 0
        and summary["real_missing_required_files"] == 5
        and intake["decision"]["P6_advanced"] is False
    ):
        raise RuntimeError("iteration 5.32 inputs changed")
    progress = {
        **prior["progress"],
        "P6_complete": False,
        "validation_v7_identity_only_v1_privacy_defect_confirmed": True,
        "validation_v7_identity_only_v1_real_bundle_acceptance_forbidden": True,
        "validation_v7_identity_only_v2_protocol_frozen": True,
        "validation_v7_v2_source_tree_commitment_salted_and_domain_separated": True,
        "validation_v7_v2_primary_and_independent_validators": 2,
        "validation_v7_v2_hostile_cases_rejected_twice": 18,
        "validation_v7_v2_required_opaque_bundle_files": 5,
        "validation_v7_v2_present_opaque_bundle_files": 0,
        "validation_v7_v2_intake_complete": False,
        "validation_v7_payload_decrypted": False,
        "validation_v7_source_runtime_graph_shape_or_outcome_accessed": False,
    }
    result = {
        "version": "FOUNDRY_READINESS_ITERATION_5_32",
        "prior_sha256": sha(prior_path),
        "phase156_privacy_audit_sha256": sha(audit_path),
        "validation_v7_v2_freeze_sha256": sha(freeze_path),
        "validation_v7_v2_intake_sha256": sha(intake_path),
        "prerequisites": prior["prerequisites"],
        "progress": progress,
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "An independent design audit falsified v1 identity hiding before "
            "any real bundle arrived: a raw public source-tree digest is "
            "dictionary-identifiable against public repositories. Phase156 "
            "preserves that valid negative with zero real exposure. V1 is "
            "retired for real intake. Corrected v2 was frozen before validator "
            "implementation and replaces every source identity, including the "
            "source tree, with a uniquely salted domain-separated commitment. "
            "Two implementations accept a synthetic v2 fixture and reject all "
            "18 frozen hostile classes. The real inbox remains at zero of five "
            "files. This repairs the intake design only; it does not provide "
            "an external corpus, accountable curator provenance, P6, V08, "
            "authorization, or a prospective result."
        ),
        "remaining_blockers": [
            "an external curator has not supplied the five-file validation-v7 v2 signed encrypted bundle",
            "curator identity, conflicts, and selection chronology need accountable out-of-band trust anchors and an external append-only timestamp or transparency-log predecessor",
            "after exact bundle and provenance freezes, the v7 seed, runner, all arm bindings, evaluator, containment, key release, and V08 receipt protocol must be frozen before decryption",
        ],
        "remediation": {
            "required": True,
            "next_action": (
                "accept only the externally curated v2 five-file bundle; "
                "reject every v1 artifact; then hash-freeze the bundle and "
                "establish accountable two-party provenance plus externally "
                "anchored ordering before any key release"
            ),
            "forbidden_shortcuts": [
                "do not accept a v1 manifest or any raw source-tree digest",
                "do not generate the real corpus, salts, trust anchors, or witness keys from Foundry",
                "do not equate self-signature with curator independence",
                "do not decrypt or enumerate payload members",
                "do not advance P2 or P6 from synthetic validator conformance",
                "do not reuse validation-v6 for the primary prospective claim",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_32.json").write_text(
        json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_32"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " integrated=10/10 v1=RETIRED v2=WAITING files=0/5"
        " hostile=18/18 decrypted=false V08=pending prospective=false"
    )


if __name__ == "__main__":
    main()
