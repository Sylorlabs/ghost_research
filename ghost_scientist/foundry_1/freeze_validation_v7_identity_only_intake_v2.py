#!/usr/bin/env python3
"""Freeze corrected validation-v7 identity-only intake v2."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/VALIDATION_V7_IDENTITY_ONLY_INTAKE_PROTOCOL_V2.json"
)
RESULT = HERE / "results/validation_v7_identity_only_intake_v2_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    phase156 = json.loads(
        (HERE / "results/phase156_validation_v7_identity_privacy_audit.json").read_text()
    )
    if not (
        all(
            sha(HERE / row["path"]) == row["sha256"]
            for row in protocol["provider_records"]
        )
        and phase156["decision"][
            "validation_v7_identity_intake_v1_allowed_for_real_bundle"
        ]
        is False
        and protocol["v1_real_bundle_acceptance_forbidden"] is True
        and protocol[
            "frozen_before_v2_validator_implementation_or_external_bundle_access"
        ]
        is True
        and protocol["commitment_policy"]["minimum_secret_salt_bits"] >= 128
        and protocol["commitment_policy"]["salts_stored_only_inside_encrypted_payload"]
        is True
        and protocol["cryptographic_policy"]["decryption_forbidden_in_this_phase"]
        is True
        and protocol["decision_rule"]["this_phase_never_closes_P6"] is True
    ):
        raise RuntimeError("validation-v7 v2 protocol cannot be frozen")
    inbox = HERE / protocol["inbox"]
    present = sorted(path.name for path in inbox.iterdir())
    if any(name != "README.md" for name in present):
        raise RuntimeError("external v7 artifact arrived before v2 freeze")
    payload = {
        "version": "FOUNDRY_VALIDATION_V7_IDENTITY_ONLY_INTAKE_FREEZE_V2",
        "status": "FROZEN_BEFORE_V2_VALIDATORS_OR_EXTERNAL_BUNDLE",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": protocol["provider_records"],
        "required_files": protocol["required_files"],
        "candidate_visible_boundary": protocol["candidate_visible_boundary"],
        "commitment_policy": protocol["commitment_policy"],
        "public_manifest_contract": protocol["public_manifest_contract"],
        "cryptographic_policy": protocol["cryptographic_policy"],
        "decision_rule": protocol["decision_rule"],
        "hostile_requirements": protocol["hostile_requirements"],
        "resource_limits": protocol["resource_limits"],
        "inbox_files_at_freeze": present,
        "v1_retired_before_real_bundle_arrival": True,
        "validation_v7_accessed": False,
        "prospective_trial_authorized": False
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_VALIDATION_V7_IDENTITY_ONLY_FREEZE_V2"
        f" status={payload['status']}"
        f" protocol_sha256={payload['protocol_sha256']}"
    )


if __name__ == "__main__":
    main()
