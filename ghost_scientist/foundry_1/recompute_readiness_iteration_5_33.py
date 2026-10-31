#!/usr/bin/env python3
"""Recompute readiness after accountable provenance v2 conformance."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_32.json"
    audit_path = RESULTS / "phase158_validation_v7_provenance_v1_enforcement_audit.json"
    freeze_path = RESULTS / "validation_v7_accountable_provenance_v2_freeze.json"
    provenance_path = RESULTS / "phase159_validation_v7_accountable_provenance_v2.json"
    prior = json.loads(prior_path.read_text())
    audit = json.loads(audit_path.read_text())
    freeze = json.loads(freeze_path.read_text())
    provenance = json.loads(provenance_path.read_text())
    summary = provenance["observed"]["summary"]
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and prior["progress"]["production_integrated_arms"] == 10
        and audit["status"]
        == "PROVENANCE_V1_ENFORCEMENT_GAPS_CONFIRMED_NO_EXTERNAL_ARTIFACTS"
        and audit["decision"]["provenance_v1_allowed_for_real_attestation"]
        is False
        and freeze["status"]
        == "FROZEN_BEFORE_V2_VALIDATORS_EXTERNAL_TRUST_OR_PROVENANCE"
        and provenance["status"] == "WAITING_EXTERNAL_SPONSOR_TRUST_ROOT"
        and provenance["operationally_valid"] is True
        and all(provenance["checks"].values())
        and summary["positive_validators"] == 2
        and summary["hostile_cases"] == 26
        and summary["hostile_rejected_twice"] == 26
        and summary["real_trust_root_present"] is False
        and summary["real_bundle_files_present"] == 0
        and summary["real_provenance_files_present"] == 0
        and provenance["decision"]["P6_advanced"] is False
    ):
        raise RuntimeError("iteration 5.33 inputs changed")
    progress = {
        **prior["progress"],
        "P6_complete": False,
        "validation_v7_provenance_v1_enforcement_gaps_confirmed": True,
        "validation_v7_provenance_v1_real_attestation_forbidden": True,
        "validation_v7_accountable_provenance_v2_protocol_frozen": True,
        "validation_v7_accountable_provenance_v2_validators": 2,
        "validation_v7_accountable_provenance_v2_hostile_rejected_twice": 26,
        "validation_v7_accountable_provenance_v2_signatures_verified": 4,
        "validation_v7_candidate_roster_nonmembership_checks": 2,
        "validation_v7_source_choice_rows_bound": 4,
        "validation_v7_real_sponsor_trust_root_present": False,
        "validation_v7_real_provenance_files_present": 0,
        "validation_v7_required_provenance_files": 13,
        "validation_v7_real_accountable_provenance_attested": False,
        "validation_v7_payload_decrypted": False,
        "validation_v7_source_runtime_graph_shape_or_outcome_accessed": False,
    }
    result = {
        "version": "FOUNDRY_READINESS_ITERATION_5_33",
        "prior_sha256": sha(prior_path),
        "phase158_enforcement_audit_sha256": sha(audit_path),
        "accountable_provenance_v2_freeze_sha256": sha(freeze_path),
        "phase159_accountable_provenance_v2_sha256": sha(provenance_path),
        "prerequisites": prior["prerequisites"],
        "progress": progress,
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "Provenance v1 was retired before external enrollment because it "
            "named a source-choice root without a byte-exact construction and "
            "provided no candidate-roster leaves for mechanical curator and "
            "reviewer nonmembership checks. Corrected v2 freezes both "
            "constructions. Two implementations accept a fully signed "
            "synthetic chain, independently derive roots, verify four RSA-PSS "
            "signatures and two roster nonmembership relations, enforce event "
            "chronology, and reject all 26 hostile classes. The real state "
            "correctly waits before the first trust boundary: no out-of-band "
            "sponsor fingerprint, v2 bundle, or provenance package exists. "
            "Mechanism conformance is not real independence evidence, P6, "
            "authorization, V08, or a prospective result."
        ),
        "remaining_blockers": [
            "an experiment sponsor must be verified out of band and its public-key fingerprint enrolled after the protocol freeze",
            "an external curator must supply the corrected five-file validation-v7 v2 bundle",
            "the sponsor, curator, independent reviewer, and external log must supply the exact thirteen-file provenance-v2 package with externally witnessed ordering",
            "after exact bundle and provenance freezes, the seed, runner, ten arm bindings, evaluator, containment, key release, and V08 receipt protocol must be frozen before decryption",
        ],
        "remediation": {
            "required": True,
            "next_action": (
                "obtain the externally verified sponsor fingerprint, then "
                "accept only the corrected v2 bundle and thirteen-file "
                "provenance-v2 package; rerun Phase157 and Phase159 unchanged"
            ),
            "forbidden_shortcuts": [
                "do not generate or approve the production sponsor, curator, reviewer, or external-log keys from Foundry",
                "do not accept provenance v1 or identity-intake v1 artifacts",
                "do not equate four passing signatures with proof of social independence or absence of off-system collusion",
                "do not decrypt, enumerate payload members, or release the matcher",
                "do not advance P2 or P6 from synthetic conformance",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_33.json").write_text(
        json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_33"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6 integrated=10/10"
        " provenance_v1=RETIRED provenance_v2=CONFORMANT"
        " real_trust=false real_bundle=0/5 real_provenance=0/13"
        " V08=pending prospective=false"
    )


if __name__ == "__main__":
    main()
