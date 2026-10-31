#!/usr/bin/env python3
"""Audit whether provenance v1's named claims are mechanically enforceable."""

from __future__ import annotations

import hashlib
import json
import pathlib

from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/VALIDATION_V7_ACCOUNTABLE_PROVENANCE_PROTOCOL_V1.json"
)
FREEZE = HERE / "results/validation_v7_accountable_provenance_v1_freeze.json"
RESULT = HERE / "results/phase158_validation_v7_provenance_v1_enforcement_audit.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    trust_root = (
        HERE
        / protocol["trust_root_directory"]
        / protocol["required_trust_root_files"][0]
    )
    provenance_present = sorted(
        path.name
        for path in (HERE / protocol["provenance_inbox"]).iterdir()
        if path.name != "README.md"
    )
    statement = protocol["provenance_statement_contract"]
    registry = protocol["trust_registry_contract"]
    observed = {
        "source_choice_root_field_named": (
            "source_choice_set_root_sha256" in statement["exact_fields"]
        ),
        "source_choice_root_construction_defined": (
            "source_choice_root_construction" in protocol
        ),
        "candidate_roster_root_named": (
            "candidate_team_roster_root_sha256" in registry["exact_fields"]
        ),
        "candidate_roster_leaf_contract_defined": (
            "candidate_team_identity_commitments" in registry["exact_fields"]
            and "candidate_roster_commitment_construction" in protocol
        ),
        "curator_reviewer_roster_nonmembership_mechanically_checkable": False,
        "real_external_trust_root_present": trust_root.exists(),
        "real_provenance_files_present": len(provenance_present),
        "payload_decrypted": False,
        "source_runtime_graph_shape_or_outcome_accessed": False,
    }
    checks = {
        "v1_freeze_preceded_audit": (
            freeze["status"]
            == "FROZEN_BEFORE_EXTERNAL_TRUST_ROOT_OR_PROVENANCE"
            and freeze["protocol_sha256"] == sha(PROTOCOL)
        ),
        "choice_root_is_named_but_algorithm_missing": (
            observed["source_choice_root_field_named"] is True
            and observed["source_choice_root_construction_defined"] is False
        ),
        "roster_root_is_named_but_leaf_contract_missing": (
            observed["candidate_roster_root_named"] is True
            and observed["candidate_roster_leaf_contract_defined"] is False
        ),
        "roster_nonmembership_not_mechanically_checkable": (
            observed[
                "curator_reviewer_roster_nonmembership_mechanically_checkable"
            ]
            is False
        ),
        "no_real_external_artifacts_arrived": (
            observed["real_external_trust_root_present"] is False
            and observed["real_provenance_files_present"] == 0
        ),
        "no_payload_decryption_or_scientific_access": (
            observed["payload_decrypted"] is False
            and observed["source_runtime_graph_shape_or_outcome_accessed"]
            is False
        ),
    }
    receipt = run_metered_tree(
        [
            "/usr/bin/python3",
            "-c",
            (
                "import json,pathlib;"
                f"p=json.loads(pathlib.Path({str(PROTOCOL)!r}).read_text());"
                "assert 'source_choice_set_root_sha256' in "
                "p['provenance_statement_contract']['exact_fields'];"
                "assert 'source_choice_root_construction' not in p;"
                "assert 'candidate_team_identity_commitments' not in "
                "p['trust_registry_contract']['exact_fields']"
            ),
        ],
        cwd=HERE,
        wall_limit_seconds=10,
        cpu_limit_seconds=5,
        rss_limit_kib=131072,
    )
    checks["independent_metered_schema_probe_passed"] = (
        receipt["returncode"] == 0
        and receipt["termination"] == "natural"
        and receipt["process_group_reaped"] is True
    )
    if not all(checks.values()):
        raise RuntimeError("provenance v1 enforcement audit changed")
    result = {
        "version": "FOUNDRY_VALIDATION_V7_PROVENANCE_V1_ENFORCEMENT_AUDIT_V1",
        "status": "PROVENANCE_V1_ENFORCEMENT_GAPS_CONFIRMED_NO_EXTERNAL_ARTIFACTS",
        "protocol_v1_sha256": sha(PROTOCOL),
        "freeze_v1_sha256": sha(FREEZE),
        "checks": checks,
        "observed": observed,
        "receipt": receipt,
        "decision": {
            "provenance_v1_allowed_for_real_attestation": False,
            "provenance_v2_required": True,
            "required_repairs": [
                "define a byte-exact source-choice set-root construction derived from all four public v2 source rows",
                "publish opaque candidate-team identity commitments under an exact roster-root construction and mechanically reject curator or reviewer membership",
            ],
            "P6_advanced": False,
            "prospective_trial_authorized": False,
        },
        "claim_boundary": {
            "specification_audit_not_real_provenance_evidence": True,
            "no_real_external_artifact_was_present": True,
            "payload_decrypted": False,
            "prospective_trial_executed": False,
        },
    }
    RESULT.write_text(
        json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE158"
        f" status={result['status']}"
        " provenance_v1=RETIRED v2_required=true P6=false"
    )


if __name__ == "__main__":
    main()
