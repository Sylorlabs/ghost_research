#!/usr/bin/env python3
"""Recompute readiness after the v7 identity-only intake boundary."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_30.json"
    freeze_path = RESULTS / "validation_v7_identity_only_intake_v1_freeze.json"
    intake_path = RESULTS / "phase155_validation_v7_identity_only_intake.json"
    prior = json.loads(prior_path.read_text())
    freeze = json.loads(freeze_path.read_text())
    intake = json.loads(intake_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and prior["progress"]["production_integrated_arms"] == 10
        and prior["prerequisites"]["P6_unchanged_prospective_freeze"]
        is False
        and freeze["status"] == "FROZEN_BEFORE_EXTERNAL_BUNDLE_ARRIVAL"
        and intake["status"]
        == "VALIDATION_V7_IDENTITY_ONLY_INTAKE_WAITING"
        and intake["operationally_valid"] is True
        and all(intake["checks"].values())
        and intake["observed"]["summary"]["positive_validators"] == 2
        and intake["observed"]["summary"]["hostile_cases"] == 16
        and intake["observed"]["summary"]["hostile_rejected_twice"] == 16
        and intake["observed"]["summary"]["real_present_required_files"] == 0
        and intake["observed"]["summary"]["real_missing_required_files"] == 5
        and intake["decision"]["P6_advanced"] is False
    ):
        raise RuntimeError("iteration 5.31 inputs changed")
    progress = {
        **prior["progress"],
        "P6_complete": False,
        "validation_v7_identity_only_protocol_frozen": True,
        "validation_v7_candidate_visible_plaintext_fields": 0,
        "validation_v7_required_opaque_bundle_files": 5,
        "validation_v7_present_opaque_bundle_files": 0,
        "validation_v7_primary_and_independent_validators": 2,
        "validation_v7_hostile_cases_rejected_twice": 16,
        "validation_v7_payload_decrypted": False,
        "validation_v7_source_runtime_graph_shape_or_outcome_accessed": False,
        "validation_v7_intake_complete": False,
    }
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_31",
        "prior_sha256": sha(prior_path),
        "validation_v7_intake_freeze_sha256": sha(freeze_path),
        "validation_v7_intake_result_sha256": sha(intake_path),
        "prerequisites": prior["prerequisites"],
        "progress": progress,
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "The 10/10 calibration arm matrix remains valid. P6 remediation "
            "now has a frozen identity-only v7 intake boundary that exposes "
            "only salted commitments, signed aggregate attestations, and an "
            "opaque ciphertext digest. Two implementations accept a synthetic "
            "3072-bit RSA-PSS signed fixture and reject all 16 frozen hostile "
            "classes. The real inbox is safely waiting with zero of five "
            "required files; no payload was decrypted and no v7 source, "
            "runtime, graph, shape, or outcome was accessed. This establishes "
            "the separation mechanism, not an independently sourced corpus, "
            "P2/P6 closure, V08, authorization, or a prospective result."
        ),
        "remaining_blockers": [
            "an external curator has not yet supplied the five-file signed encrypted validation-v7 bundle",
            "after bundle intake, curator independence and the revealed provenance commitments still require a separate pre-decryption authorization design",
            "the exact v7 seed, runner, all arm bindings, evaluator, containment, and V08 receipt protocol must be frozen before decryption or runtime access",
        ],
        "remediation": {
            "required": True,
            "next_action": (
                "accept only the externally curated five-file opaque bundle, "
                "rerun phase155 without protocol changes, then freeze its exact "
                "digest and an independent curator-provenance attestation "
                "before designing the authorization and key-release overlay"
            ),
            "forbidden_shortcuts": [
                "do not create or select the validation-v7 corpus from candidate-visible model semantics",
                "do not place a decryption or private signing key in the repository or inbox",
                "do not decrypt or list payload members during identity-only intake",
                "do not treat synthetic validator conformance as a real corpus",
                "do not advance P2 or P6 from transport integrity alone",
                "do not reuse validation-v6 for the primary prospective claim",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_31.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_31"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " integrated=10/10 v7_intake=WAITING files=0/5"
        " decrypted=false V08=pending prospective=false"
    )


if __name__ == "__main__":
    main()
