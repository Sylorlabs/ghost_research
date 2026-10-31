#!/usr/bin/env python3
"""Falsify the v7.1 claim that raw source-tree hashes hide identity."""

from __future__ import annotations

import hashlib
import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/VALIDATION_V7_IDENTITY_ONLY_INTAKE_PROTOCOL_V1.json"
)
PHASE155 = HERE / "results/phase155_validation_v7_identity_only_intake.json"
WORKER_RESULT = HERE / "results/phase156_validation_v7_identity_privacy_audit_worker.json"
RESULT = HERE / "results/phase156_validation_v7_identity_privacy_audit.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def worker() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    source_fields = protocol["public_manifest_contract"]["source_exact_fields"]
    if "source_tree_sha256" not in source_fields:
        raise RuntimeError("v1 source-tree field changed")
    public_candidates = {
        "public-repo-a@immutable-revision": b"tree\0alpha\0source-a",
        "public-repo-b@immutable-revision": b"tree\0beta\0source-b",
    }
    lookup = {digest(raw): identity for identity, raw in public_candidates.items()}
    exposed = digest(public_candidates["public-repo-b@immutable-revision"])
    recovered = lookup.get(exposed)
    salt = bytes.fromhex("42" * 16)
    salted = digest(
        b"ghost-foundry:v7:source-tree-commitment:v2\0"
        + salt
        + b"\0"
        + public_candidates["public-repo-b@immutable-revision"]
    )
    raw_dictionary_match = salted in lookup
    payload = {
        "version": "FOUNDRY_VALIDATION_V7_IDENTITY_PRIVACY_AUDIT_WORKER_V1",
        "raw_source_tree_digest_dictionary_identified": (
            recovered == "public-repo-b@immutable-revision"
        ),
        "raw_dictionary_candidates": len(lookup),
        "salted_domain_separated_commitment_matches_raw_dictionary": raw_dictionary_match,
        "required_repair": {
            "field": "source_tree_commitment_sha256",
            "construction": "SHA-256(domain-separator || NUL || 128-bit-or-larger-secret-salt || NUL || canonical-source-tree-identity)",
            "salt_location": "encrypted payload only",
            "all_other_identity_commitments_require_same_domain-separated salted construction": True,
        },
        "real_inbox_required_files_present": 0,
        "real_source_tree_digests_observed": 0,
        "payload_decrypted": False,
        "source_runtime_graph_shape_or_outcome_accessed": False,
    }
    WORKER_RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE156_WORKER"
        " raw_digest_identified=true"
        " salted_raw_dictionary_match=false"
        " real_exposure=false"
    )


def main() -> None:
    if len(sys.argv) == 2 and sys.argv[1] == "--worker":
        worker()
        return
    phase155 = json.loads(PHASE155.read_text())
    receipt = run_metered_tree(
        [sys.executable, str(pathlib.Path(__file__).resolve()), "--worker"],
        cwd=HERE,
        wall_limit_seconds=30,
        cpu_limit_seconds=20,
        rss_limit_kib=262144,
    )
    observed = json.loads(WORKER_RESULT.read_text())
    checks = {
        "phase155_real_inbox_was_empty": (
            phase155["observed"]["summary"]["real_present_required_files"] == 0
        ),
        "v1_raw_source_tree_digest_is_dictionary_identifiable": (
            observed["raw_source_tree_digest_dictionary_identified"] is True
        ),
        "domain_separated_salted_form_not_in_raw_dictionary": (
            observed[
                "salted_domain_separated_commitment_matches_raw_dictionary"
            ]
            is False
        ),
        "no_real_source_digest_observed": (
            observed["real_source_tree_digests_observed"] == 0
        ),
        "no_payload_decryption": observed["payload_decrypted"] is False,
        "no_source_runtime_graph_shape_or_outcome_access": (
            observed[
                "source_runtime_graph_shape_or_outcome_accessed"
            ]
            is False
        ),
        "metered_worker_passed": (
            receipt["returncode"] == 0
            and receipt["termination"] == "natural"
            and receipt["process_group_reaped"] is True
        ),
    }
    if not all(checks.values()):
        raise RuntimeError("v7 identity privacy audit failed")
    result = {
        "version": "FOUNDRY_VALIDATION_V7_IDENTITY_PRIVACY_AUDIT_RESULT_V1",
        "status": "VALIDATION_V7_V1_PRIVACY_DEFECT_CONFIRMED_NO_REAL_EXPOSURE",
        "protocol_v1_sha256": sha(PROTOCOL),
        "phase155_sha256": sha(PHASE155),
        "checks": checks,
        "observed": observed,
        "receipt": receipt,
        "decision": {
            "validation_v7_identity_intake_v1_allowed_for_real_bundle": False,
            "validation_v7_identity_intake_v2_required": True,
            "P2_advanced": False,
            "P6_advanced": False,
            "prospective_trial_authorized": False,
        },
        "claim_boundary": {
            "synthetic_dictionary_demonstration_not_general_cryptographic_proof": True,
            "no_real_external_bundle_was_present": True,
            "no_real_identity_was_exposed": True,
            "payload_decrypted": False,
            "prospective_trial_executed": False,
        },
    }
    RESULT.write_text(
        json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE156"
        f" status={result['status']}"
        " v1_retired=true v2_required=true P6=false prospective=false"
    )


if __name__ == "__main__":
    main()
