#!/usr/bin/env python3
"""Primary validator for accountable validation-v7 provenance v2."""

from __future__ import annotations

import datetime
import hashlib
import json
import pathlib
import re
import subprocess
from typing import Any

from validation_v7_identity_only_intake_v2 import (
    V7V2Reject,
    validate_complete as validate_v2_bundle,
)


class V7ProvenanceV2Reject(ValueError):
    pass


HEX = re.compile(r"^[0-9a-f]{64}$")
OPAQUE_ACTOR = re.compile(r"^actor_[0-9a-f]{24}$")
OPAQUE_LOG = re.compile(r"^log_[0-9a-f]{24}$")
ATTESTATION = re.compile(r"^att_[0-9a-f]{32}$")
UTC = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")


def canonical(value: object) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n"
    ).encode()


def sha_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def sha(path: pathlib.Path) -> str:
    return sha_bytes(path.read_bytes())


def timestamp(value: str) -> datetime.datetime:
    if UTC.fullmatch(value) is None:
        raise V7ProvenanceV2Reject("timestamp format")
    return datetime.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(
        tzinfo=datetime.timezone.utc
    )


def openssl(arguments: list[str]) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["openssl", *arguments],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def key_fingerprint(path: pathlib.Path) -> tuple[str, int]:
    if b"PRIVATE KEY" in path.read_bytes():
        raise V7ProvenanceV2Reject("private key")
    info = openssl(["pkey", "-pubin", "-in", str(path), "-text", "-noout"])
    match = re.search(rb"Public-Key: \((\d+) bit\)", info.stdout)
    der = openssl(["pkey", "-pubin", "-in", str(path), "-outform", "DER"])
    if (
        info.returncode
        or der.returncode
        or match is None
        or int(match.group(1)) < 3072
    ):
        raise V7ProvenanceV2Reject("public key")
    return sha_bytes(der.stdout), int(match.group(1))


def verify_signature(
    public_key: pathlib.Path, signature: pathlib.Path, message: pathlib.Path
) -> None:
    result = openssl(
        [
            "dgst",
            "-sha256",
            "-verify",
            str(public_key),
            "-signature",
            str(signature),
            "-sigopt",
            "rsa_padding_mode:pss",
            "-sigopt",
            "rsa_pss_saltlen:digest",
            str(message),
        ]
    )
    if result.returncode:
        raise V7ProvenanceV2Reject("signature")


def load_canonical(path: pathlib.Path) -> dict[str, Any]:
    raw = path.read_bytes()
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as error:
        raise V7ProvenanceV2Reject("JSON") from error
    if not isinstance(value, dict) or raw != canonical(value):
        raise V7ProvenanceV2Reject("noncanonical JSON")
    return value


def roster_root(commitments: list[str], protocol: dict[str, Any]) -> str:
    policy = protocol["commitment_constructions"]["candidate_roster_root"]
    if (
        not policy["minimum_leaves"]
        <= len(commitments)
        <= policy["maximum_leaves"]
        or len(set(commitments)) != len(commitments)
        or any(HEX.fullmatch(value) is None for value in commitments)
    ):
        raise V7ProvenanceV2Reject("candidate roster leaves")
    leaves = sorted(bytes.fromhex(value) for value in commitments)
    return sha_bytes(
        policy["domain_separator"].encode() + b"\0" + b"".join(leaves)
    )


def source_choice_root(
    source_rows: list[dict[str, Any]], protocol: dict[str, Any]
) -> str:
    policy = protocol["commitment_constructions"]["source_choice_set_root"]
    if len(source_rows) != policy["leaves"]:
        raise V7ProvenanceV2Reject("source-choice leaves")
    leaves = sorted(hashlib.sha256(canonical(row)).digest() for row in source_rows)
    return sha_bytes(
        policy["domain_separator"].encode() + b"\0" + b"".join(leaves)
    )


def validate_complete(
    trust_root: pathlib.Path,
    provenance: pathlib.Path,
    bundle: pathlib.Path,
    protocol: dict[str, Any],
    intake_protocol: dict[str, Any],
) -> dict[str, Any]:
    trust_required = set(protocol["required_trust_root_files"])
    trust_paths = {path.name: path for path in trust_root.iterdir()}
    if set(trust_paths) - trust_required - {"README.md"} or not trust_required <= set(
        trust_paths
    ):
        raise V7ProvenanceV2Reject("trust-root file set")
    required = set(protocol["required_provenance_files"])
    paths = {path.name: path for path in provenance.iterdir()}
    if set(paths) - required - {"README.md"} or not required <= set(paths):
        raise V7ProvenanceV2Reject("provenance file set")
    if any(
        path.is_symlink() or not path.is_file()
        for path in [*trust_paths.values(), *paths.values()]
    ):
        raise V7ProvenanceV2Reject("entry type")
    if any(b"PRIVATE KEY" in path.read_bytes() for path in paths.values()):
        raise V7ProvenanceV2Reject("private key material")
    sponsor_fingerprint_raw = trust_paths[
        "authorized_sponsor_fingerprint.sha256"
    ].read_bytes()
    if (
        len(sponsor_fingerprint_raw) != 65
        or sponsor_fingerprint_raw[-1:] != b"\n"
        or HEX.fullmatch(sponsor_fingerprint_raw[:-1].decode(errors="ignore"))
        is None
    ):
        raise V7ProvenanceV2Reject("external sponsor fingerprint")
    sponsor_fingerprint = sponsor_fingerprint_raw[:-1].decode()
    bundle_result = validate_v2_bundle(bundle, intake_protocol)
    manifest_path = bundle / "public_manifest.v2.json"
    manifest = load_canonical(manifest_path)
    registry_path = paths["trust_registry.v2.json"]
    boundary_path = paths["candidate_boundary.v2.json"]
    statement_path = paths["provenance_statement.v2.json"]
    log_path = paths["external_log_entry.v2.json"]
    registry = load_canonical(registry_path)
    boundary = load_canonical(boundary_path)
    statement = load_canonical(statement_path)
    log_entry = load_canonical(log_path)
    sponsor_key = paths["sponsor_public_key.pem"]
    curator_key = paths["curator_public_key.pem"]
    reviewer_key = paths["reviewer_public_key.pem"]
    log_key = paths["external_log_public_key.pem"]
    sponsor_fp, sponsor_bits = key_fingerprint(sponsor_key)
    curator_fp, curator_bits = key_fingerprint(curator_key)
    reviewer_fp, reviewer_bits = key_fingerprint(reviewer_key)
    log_fp, log_bits = key_fingerprint(log_key)
    if sponsor_fp != sponsor_fingerprint:
        raise V7ProvenanceV2Reject("untrusted sponsor key")
    registry_contract = protocol["trust_registry_contract"]
    if (
        set(registry) != set(registry_contract["exact_fields"])
        or registry.get("version") != registry_contract["version"]
        or registry.get("scope") != registry_contract["scope"]
        or registry.get("registration_method")
        != registry_contract["registration_method"]
        or registry.get("sponsor_key_fingerprint_sha256") != sponsor_fp
    ):
        raise V7ProvenanceV2Reject("trust registry schema")
    enrolled = timestamp(registry["enrolled_utc"])
    roster = registry["candidate_team_identity_commitments"]
    if not isinstance(roster, list):
        raise V7ProvenanceV2Reject("candidate roster")
    computed_roster_root = roster_root(roster, protocol)
    if registry["candidate_team_roster_root_sha256"] != computed_roster_root:
        raise V7ProvenanceV2Reject("candidate roster root")
    actor_fields = set(registry_contract["actor_exact_fields"])
    actors = [registry["curator"], registry["reviewer"]]
    purposes = [
        registry_contract["curator_key_purpose"],
        registry_contract["reviewer_key_purpose"],
    ]
    fingerprints = [curator_fp, reviewer_fp]
    for actor, purpose, fingerprint in zip(actors, purposes, fingerprints):
        if (
            not isinstance(actor, dict)
            or set(actor) != actor_fields
            or OPAQUE_ACTOR.fullmatch(actor.get("opaque_actor_id", "")) is None
            or any(
                HEX.fullmatch(actor.get(field, "")) is None
                for field in (
                    "legal_identity_commitment_sha256",
                    "organization_commitment_sha256",
                    "public_key_fingerprint_sha256",
                    "sponsor_review_receipt_sha256",
                )
            )
            or actor["public_key_fingerprint_sha256"] != fingerprint
            or actor["key_purpose"] != purpose
            or actor["conflict_check_completed"] is not True
            or actor["legal_identity_commitment_sha256"] in roster
        ):
            raise V7ProvenanceV2Reject("actor registry")
    for field in (
        "legal_identity_commitment_sha256",
        "organization_commitment_sha256",
        "public_key_fingerprint_sha256",
        "sponsor_review_receipt_sha256",
    ):
        if actors[0][field] == actors[1][field]:
            raise V7ProvenanceV2Reject("actor overlap")
    log_record = registry["external_log"]
    log_fields = set(registry_contract["external_log_exact_fields"])
    if (
        not isinstance(log_record, dict)
        or set(log_record) != log_fields
        or OPAQUE_LOG.fullmatch(log_record.get("opaque_log_id", "")) is None
        or any(
            HEX.fullmatch(log_record.get(field, "")) is None
            for field in (
                "organization_commitment_sha256",
                "public_key_fingerprint_sha256",
                "sponsor_review_receipt_sha256",
            )
        )
        or log_record["public_key_fingerprint_sha256"] != log_fp
        or log_record["key_purpose"]
        != registry_contract["external_log_key_purpose"]
        or log_record["organization_commitment_sha256"]
        in {actor["organization_commitment_sha256"] for actor in actors}
        or log_record["sponsor_review_receipt_sha256"]
        in {actor["sponsor_review_receipt_sha256"] for actor in actors}
    ):
        raise V7ProvenanceV2Reject("external log registry")
    verify_signature(
        sponsor_key, paths["trust_registry.v2.sig"], registry_path
    )
    boundary_contract = protocol["candidate_boundary_contract"]
    if (
        set(boundary) != set(boundary_contract["exact_fields"])
        or boundary.get("version") != boundary_contract["version"]
        or boundary.get("matcher_released") is not False
        or boundary.get("candidate_team_roster_root_sha256")
        != computed_roster_root
        or any(
            boundary.get(field) != value
            for field, value in protocol["candidate_snapshot_contract"].items()
        )
        or HEX.fullmatch(boundary.get("matcher_release_policy_sha256", ""))
        is None
    ):
        raise V7ProvenanceV2Reject("candidate boundary")
    snapshot = timestamp(boundary["snapshot_created_utc"])
    verify_signature(
        sponsor_key, paths["candidate_boundary.v2.sig"], boundary_path
    )
    statement_contract = protocol["provenance_statement_contract"]
    expected_choice_root = source_choice_root(manifest["sources"], protocol)
    if (
        set(statement) != set(statement_contract["exact_fields"])
        or statement.get("version") != statement_contract["version"]
        or ATTESTATION.fullmatch(statement.get("attestation_id", "")) is None
        or statement.get("corpus_id") != bundle_result["corpus_id"]
        or statement.get("public_manifest_sha256") != sha(manifest_path)
        or statement.get("payload_ciphertext_sha256")
        != bundle_result["payload_sha256"]
        or statement.get("source_choice_set_root_sha256")
        != expected_choice_root
        or statement.get("source_count") != statement_contract["source_count"]
        or statement.get("trust_registry_sha256") != sha(registry_path)
        or statement.get("candidate_boundary_sha256") != sha(boundary_path)
        or HEX.fullmatch(statement.get("selection_log_commitment_sha256", ""))
        is None
        or statement.get("statements")
        != statement_contract["statements_exact"]
        or statement.get("claim_boundary")
        != statement_contract["claim_boundary_exact"]
    ):
        raise V7ProvenanceV2Reject("provenance statement")
    choices = timestamp(statement["choices_finalized_utc"])
    issued = timestamp(statement["issued_utc"])
    verify_signature(
        curator_key, paths["curator_statement.sig"], statement_path
    )
    verify_signature(
        reviewer_key, paths["reviewer_statement.sig"], statement_path
    )
    log_contract = protocol["external_log_contract"]
    if (
        set(log_entry) != set(log_contract["exact_fields"])
        or log_entry.get("version") != log_contract["version"]
        or log_entry.get("opaque_log_id") != log_record["opaque_log_id"]
        or type(log_entry.get("sequence_number")) is not int
        or log_entry["sequence_number"] < log_contract["sequence_number_minimum"]
        or HEX.fullmatch(log_entry.get("previous_checkpoint_sha256", "")) is None
        or log_entry.get("provenance_statement_sha256") != sha(statement_path)
        or log_entry.get("selection_log_commitment_sha256")
        != statement["selection_log_commitment_sha256"]
        or log_entry.get("source_choice_set_root_sha256")
        != expected_choice_root
    ):
        raise V7ProvenanceV2Reject("external log entry")
    integrated = timestamp(log_entry["integrated_utc"])
    verify_signature(
        log_key, paths["external_log_entry.v2.sig"], log_path
    )
    if not enrolled <= snapshot <= choices <= issued <= integrated:
        raise V7ProvenanceV2Reject("chronology")
    return {
        "status": protocol["decision_rule"]["mechanism_complete_label"],
        "corpus_id": statement["corpus_id"],
        "source_count": statement["source_count"],
        "candidate_roster_members": len(roster),
        "candidate_roster_root_sha256": computed_roster_root,
        "source_choice_set_root_sha256": expected_choice_root,
        "sponsor_key_fingerprint_sha256": sponsor_fp,
        "curator_key_fingerprint_sha256": curator_fp,
        "reviewer_key_fingerprint_sha256": reviewer_fp,
        "external_log_key_fingerprint_sha256": log_fp,
        "minimum_key_bits": min(
            sponsor_bits, curator_bits, reviewer_bits, log_bits
        ),
        "signatures_verified": 4,
        "roster_nonmembership_checks": 2,
        "chronology_relations_verified": 4,
        "matcher_released": False,
        "social_independence_cryptographically_proved": False,
        "payload_decrypted": False,
    }


def inspect_state(
    trust_root: pathlib.Path,
    provenance: pathlib.Path,
    bundle: pathlib.Path,
    protocol: dict[str, Any],
    intake_protocol: dict[str, Any],
) -> dict[str, Any]:
    trust_file = trust_root / protocol["required_trust_root_files"][0]
    if not trust_file.exists():
        extras = {
            path.name
            for path in trust_root.iterdir()
            if path.name != "README.md"
        }
        if extras:
            raise V7ProvenanceV2Reject("unknown trust-root file")
        return {
            "status": "WAITING_EXTERNAL_SPONSOR_TRUST_ROOT",
            "trust_root_present": False,
            "bundle_files_present": 0,
            "provenance_files_present": 0,
            "payload_decrypted": False,
        }
    bundle_required = set(intake_protocol["required_files"])
    bundle_names = {path.name for path in bundle.iterdir()}
    bundle_present = len(bundle_required & bundle_names)
    if bundle_present != len(bundle_required):
        return {
            "status": "WAITING_VALIDATION_V7_V2_BUNDLE",
            "trust_root_present": True,
            "bundle_files_present": bundle_present,
            "provenance_files_present": 0,
            "payload_decrypted": False,
        }
    provenance_required = set(protocol["required_provenance_files"])
    provenance_names = {path.name for path in provenance.iterdir()}
    provenance_present = len(provenance_required & provenance_names)
    if provenance_present != len(provenance_required):
        if provenance_names - provenance_required - {"README.md"}:
            raise V7ProvenanceV2Reject("unknown provenance file")
        return {
            "status": "WAITING_ACCOUNTABLE_PROVENANCE_V2",
            "trust_root_present": True,
            "bundle_files_present": bundle_present,
            "provenance_files_present": provenance_present,
            "payload_decrypted": False,
        }
    return validate_complete(
        trust_root, provenance, bundle, protocol, intake_protocol
    )
