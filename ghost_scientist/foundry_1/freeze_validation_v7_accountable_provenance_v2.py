#!/usr/bin/env python3
"""Freeze corrected accountable provenance v2 before external enrollment."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/VALIDATION_V7_ACCOUNTABLE_PROVENANCE_PROTOCOL_V2.json"
)
RESULT = HERE / "results/validation_v7_accountable_provenance_v2_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    audit = json.loads(
        (HERE / "results/phase158_validation_v7_provenance_v1_enforcement_audit.json").read_text()
    )
    trust_file = (
        HERE
        / protocol["trust_root_directory"]
        / protocol["required_trust_root_files"][0]
    )
    provenance_files = sorted(
        path.name
        for path in (HERE / protocol["provenance_inbox"]).iterdir()
        if path.name != "README.md"
    )
    if not (
        all(
            sha(HERE / row["path"]) == row["sha256"]
            for row in protocol["provider_records"]
        )
        and audit["decision"]["provenance_v1_allowed_for_real_attestation"]
        is False
        and protocol["v1_real_attestation_acceptance_forbidden"] is True
        and protocol["commitment_constructions"]["source_choice_set_root"][
            "leaves"
        ]
        == 4
        and protocol["commitment_constructions"]["candidate_roster_root"][
            "minimum_leaves"
        ]
        >= 1
        and protocol["trust_registry_contract"][
            "curator_and_reviewer_identity_commitments_must_not_be_candidate_roster_members"
        ]
        is True
        and protocol["decision_rule"]["never_label_as_independence_proved"]
        is True
        and protocol["decision_rule"][
            "this_phase_never_closes_P6_or_authorizes_decryption"
        ]
        is True
        and len(protocol["required_provenance_files"]) == 13
        and len(protocol["hostile_requirements"]["must_cover"]) == 26
    ):
        raise RuntimeError("accountable provenance v2 cannot freeze")
    if trust_file.exists() or provenance_files:
        raise RuntimeError("external provenance state arrived before v2 freeze")
    result = {
        "version": "FOUNDRY_VALIDATION_V7_ACCOUNTABLE_PROVENANCE_FREEZE_V2",
        "status": "FROZEN_BEFORE_V2_VALIDATORS_EXTERNAL_TRUST_OR_PROVENANCE",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": protocol["provider_records"],
        "candidate_snapshot_contract": protocol["candidate_snapshot_contract"],
        "commitment_constructions": protocol["commitment_constructions"],
        "trust_registry_contract": protocol["trust_registry_contract"],
        "candidate_boundary_contract": protocol["candidate_boundary_contract"],
        "provenance_statement_contract": protocol[
            "provenance_statement_contract"
        ],
        "external_log_contract": protocol["external_log_contract"],
        "ordering_contract": protocol["ordering_contract"],
        "cryptographic_policy": protocol["cryptographic_policy"],
        "decision_rule": protocol["decision_rule"],
        "hostile_requirements": protocol["hostile_requirements"],
        "resource_limits": protocol["resource_limits"],
        "provenance_v1_retired": True,
        "external_trust_root_present_at_freeze": False,
        "provenance_files_at_freeze": provenance_files,
        "payload_decrypted": False,
        "prospective_trial_authorized": False
    }
    RESULT.write_text(
        json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_VALIDATION_V7_ACCOUNTABLE_PROVENANCE_FREEZE_V2"
        f" status={result['status']}"
        f" protocol_sha256={result['protocol_sha256']}"
    )


if __name__ == "__main__":
    main()
