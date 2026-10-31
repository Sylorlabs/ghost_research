#!/usr/bin/env python3
"""Freeze the validation-v7 identity-only intake before bundle arrival."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/VALIDATION_V7_IDENTITY_ONLY_INTAKE_PROTOCOL_V1.json"
)
RESULT = HERE / "results/validation_v7_identity_only_intake_v1_freeze.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    if not (
        all(
            sha(HERE / row["path"]) == row["sha256"]
            for row in protocol["provider_records"]
        )
        and protocol[
            "frozen_before_validator_implementation_or_external_bundle_access"
        ]
        is True
        and protocol["cryptographic_policy"]["decryption_forbidden_in_this_phase"]
        is True
        and protocol["decision_rule"]["this_phase_never_closes_P6"] is True
        and protocol["public_manifest_contract"]["sources"] == 4
    ):
        raise RuntimeError("validation-v7 intake protocol cannot be frozen")
    inbox = HERE / protocol["inbox"]
    present = (
        sorted(path.name for path in inbox.iterdir())
        if inbox.exists()
        else []
    )
    if any(name in protocol["required_files"] for name in present):
        raise RuntimeError("external v7 bundle arrived before protocol freeze")
    payload = {
        "version": "FOUNDRY_VALIDATION_V7_IDENTITY_ONLY_INTAKE_FREEZE_V1",
        "status": "FROZEN_BEFORE_EXTERNAL_BUNDLE_ARRIVAL",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": protocol["provider_records"],
        "required_files": protocol["required_files"],
        "candidate_visible_boundary": protocol["candidate_visible_boundary"],
        "public_manifest_contract": protocol["public_manifest_contract"],
        "cryptographic_policy": protocol["cryptographic_policy"],
        "decision_rule": protocol["decision_rule"],
        "resource_limits": protocol["resource_limits"],
        "inbox_files_at_freeze": present,
        "frozen_before_validator_implementation_or_external_bundle_access": True,
        "validation_v7_accessed": False,
        "prospective_trial_authorized": False
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_VALIDATION_V7_IDENTITY_ONLY_FREEZE"
        f" status={payload['status']}"
        f" protocol_sha256={payload['protocol_sha256']}"
    )


if __name__ == "__main__":
    main()
