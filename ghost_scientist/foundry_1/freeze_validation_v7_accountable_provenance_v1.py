#!/usr/bin/env python3
"""Freeze accountable v7 provenance before trust-root enrollment."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/VALIDATION_V7_ACCOUNTABLE_PROVENANCE_PROTOCOL_V1.json"
)
RESULT = HERE / "results/validation_v7_accountable_provenance_v1_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    forged = json.loads((HERE / "results/forged_pareto_tools.json").read_text())
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
        and forged["fixed_portfolio_sha256"]
        == protocol["candidate_snapshot_contract"]["fixed_portfolio_sha256"]
        and protocol["decision_rule"]["never_label_as_independence_proved"]
        is True
        and protocol["decision_rule"][
            "this_phase_never_closes_P6_or_authorizes_decryption"
        ]
        is True
        and protocol["ordering_contract"][
            "future_matcher_release_receipt_must_name_log_entry_as_predecessor"
        ]
        is True
        and protocol["provenance_statement_contract"]["source_count"] == 4
        and len(protocol["required_provenance_files"]) == 13
        and len(protocol["hostile_requirements"]["must_cover"]) == 24
    ):
        raise RuntimeError("accountable provenance protocol cannot freeze")
    if trust_file.exists():
        raise RuntimeError("external sponsor trust root enrolled before freeze")
    if provenance_files:
        raise RuntimeError("provenance artifacts arrived before freeze")
    result = {
        "version": "FOUNDRY_VALIDATION_V7_ACCOUNTABLE_PROVENANCE_FREEZE_V1",
        "status": "FROZEN_BEFORE_EXTERNAL_TRUST_ROOT_OR_PROVENANCE",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": protocol["provider_records"],
        "candidate_snapshot_contract": protocol["candidate_snapshot_contract"],
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
        "external_trust_root_present_at_freeze": False,
        "provenance_files_at_freeze": provenance_files,
        "payload_decrypted": False,
        "prospective_trial_authorized": False
    }
    RESULT.write_text(
        json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_VALIDATION_V7_ACCOUNTABLE_PROVENANCE_FREEZE"
        f" status={result['status']}"
        f" protocol_sha256={result['protocol_sha256']}"
    )


if __name__ == "__main__":
    main()
