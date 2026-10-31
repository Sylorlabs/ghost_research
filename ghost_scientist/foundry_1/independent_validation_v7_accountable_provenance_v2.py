#!/usr/bin/env python3
"""Independent implementation of accountable provenance v2 validation."""

from __future__ import annotations

import datetime
import hashlib
import json
import pathlib
import re
import subprocess
from typing import Any

from independent_validation_v7_identity_only_intake_v2 import (
    IndependentV7V2Reject,
    verify_complete as verify_v2_bundle,
)


class IndependentProvenanceV2Reject(ValueError):
    pass


HEX = re.compile(r"[0-9a-f]{64}")


def encode(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode() + b"\n"


def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def read_json(path: pathlib.Path) -> dict[str, Any]:
    raw = path.read_bytes()
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as error:
        raise IndependentProvenanceV2Reject("JSON") from error
    if type(value) is not dict or raw != encode(value):
        raise IndependentProvenanceV2Reject("canonical JSON")
    return value


def moment(value: object) -> int:
    if not isinstance(value, str) or re.fullmatch(
        r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", value
    ) is None:
        raise IndependentProvenanceV2Reject("time")
    return int(
        datetime.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
        .replace(tzinfo=datetime.timezone.utc)
        .timestamp()
    )


def crypto(args: list[str]) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["openssl", *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def public_identity(path: pathlib.Path) -> tuple[str, int]:
    raw = path.read_bytes()
    if b"PRIVATE KEY" in raw:
        raise IndependentProvenanceV2Reject("private key")
    details = crypto(["pkey", "-pubin", "-in", str(path), "-text", "-noout"])
    size = re.search(rb"Public-Key: \((\d+) bit\)", details.stdout)
    der = crypto(["pkey", "-pubin", "-in", str(path), "-outform", "DER"])
    if (
        details.returncode != 0
        or der.returncode != 0
        or size is None
        or int(size.group(1)) < 3072
    ):
        raise IndependentProvenanceV2Reject("RSA public key")
    return digest(der.stdout), int(size.group(1))


def signed(key: pathlib.Path, signature: pathlib.Path, message: pathlib.Path) -> None:
    result = crypto(
        [
            "dgst",
            "-sha256",
            "-verify",
            str(key),
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
        raise IndependentProvenanceV2Reject("bad signature")


def compute_roster(values: list[str], protocol: dict[str, Any]) -> str:
    rule = protocol["commitment_constructions"]["candidate_roster_root"]
    if (
        not rule["minimum_leaves"] <= len(values) <= rule["maximum_leaves"]
        or len(values) != len(set(values))
        or any(HEX.fullmatch(value) is None for value in values)
    ):
        raise IndependentProvenanceV2Reject("roster leaves")
    body = b"".join(sorted(map(bytes.fromhex, values)))
    return digest(rule["domain_separator"].encode() + b"\0" + body)


def compute_choices(rows: list[dict[str, Any]], protocol: dict[str, Any]) -> str:
    rule = protocol["commitment_constructions"]["source_choice_set_root"]
    if len(rows) != rule["leaves"]:
        raise IndependentProvenanceV2Reject("choice leaves")
    leaves = [hashlib.sha256(encode(row)).digest() for row in rows]
    return digest(rule["domain_separator"].encode() + b"\0" + b"".join(sorted(leaves)))


def verify_complete(
    trust_root: pathlib.Path,
    provenance: pathlib.Path,
    bundle: pathlib.Path,
    protocol: dict[str, Any],
    intake_protocol: dict[str, Any],
) -> dict[str, Any]:
    trust_names = {path.name: path for path in trust_root.iterdir()}
    provenance_names = {path.name: path for path in provenance.iterdir()}
    trust_required = set(protocol["required_trust_root_files"])
    required = set(protocol["required_provenance_files"])
    if (
        set(trust_names) - trust_required - {"README.md"}
        or not trust_required <= set(trust_names)
        or set(provenance_names) - required - {"README.md"}
        or not required <= set(provenance_names)
        or any(
            path.is_symlink() or not path.is_file()
            for path in [*trust_names.values(), *provenance_names.values()]
        )
    ):
        raise IndependentProvenanceV2Reject("file boundary")
    trust_raw = trust_names["authorized_sponsor_fingerprint.sha256"].read_bytes()
    if (
        len(trust_raw) != 65
        or trust_raw[64:] != b"\n"
        or HEX.fullmatch(trust_raw[:64].decode(errors="ignore")) is None
    ):
        raise IndependentProvenanceV2Reject("sponsor anchor")
    try:
        bundle_result = verify_v2_bundle(bundle, intake_protocol)
    except IndependentV7V2Reject as error:
        raise IndependentProvenanceV2Reject("v2 bundle") from error
    manifest_path = bundle / "public_manifest.v2.json"
    manifest = read_json(manifest_path)
    documents = {
        "registry": read_json(provenance_names["trust_registry.v2.json"]),
        "boundary": read_json(provenance_names["candidate_boundary.v2.json"]),
        "statement": read_json(provenance_names["provenance_statement.v2.json"]),
        "log": read_json(provenance_names["external_log_entry.v2.json"]),
    }
    key_paths = {
        "sponsor": provenance_names["sponsor_public_key.pem"],
        "curator": provenance_names["curator_public_key.pem"],
        "reviewer": provenance_names["reviewer_public_key.pem"],
        "log": provenance_names["external_log_public_key.pem"],
    }
    identities = {name: public_identity(path) for name, path in key_paths.items()}
    if identities["sponsor"][0] != trust_raw[:64].decode():
        raise IndependentProvenanceV2Reject("sponsor trust mismatch")
    registry = documents["registry"]
    rc = protocol["trust_registry_contract"]
    if (
        set(registry) != set(rc["exact_fields"])
        or registry.get("version") != rc["version"]
        or registry.get("scope") != rc["scope"]
        or registry.get("registration_method") != rc["registration_method"]
        or registry.get("sponsor_key_fingerprint_sha256")
        != identities["sponsor"][0]
    ):
        raise IndependentProvenanceV2Reject("registry schema")
    roster = registry.get("candidate_team_identity_commitments")
    if type(roster) is not list:
        raise IndependentProvenanceV2Reject("roster")
    roster_digest = compute_roster(roster, protocol)
    if roster_digest != registry.get("candidate_team_roster_root_sha256"):
        raise IndependentProvenanceV2Reject("roster root")
    actors = [registry.get("curator"), registry.get("reviewer")]
    actor_keys = ["curator", "reviewer"]
    actor_purposes = [rc["curator_key_purpose"], rc["reviewer_key_purpose"]]
    actor_fields = set(rc["actor_exact_fields"])
    for actor, key_name, purpose in zip(actors, actor_keys, actor_purposes):
        if (
            type(actor) is not dict
            or set(actor) != actor_fields
            or re.fullmatch(r"actor_[0-9a-f]{24}", actor.get("opaque_actor_id", ""))
            is None
            or any(
                HEX.fullmatch(actor.get(field, "")) is None
                for field in (
                    "legal_identity_commitment_sha256",
                    "organization_commitment_sha256",
                    "public_key_fingerprint_sha256",
                    "sponsor_review_receipt_sha256",
                )
            )
            or actor["legal_identity_commitment_sha256"] in roster
            or actor["public_key_fingerprint_sha256"] != identities[key_name][0]
            or actor["key_purpose"] != purpose
            or actor["conflict_check_completed"] is not True
        ):
            raise IndependentProvenanceV2Reject("actor")
    unique_fields = (
        "legal_identity_commitment_sha256",
        "organization_commitment_sha256",
        "public_key_fingerprint_sha256",
        "sponsor_review_receipt_sha256",
    )
    if any(actors[0][field] == actors[1][field] for field in unique_fields):
        raise IndependentProvenanceV2Reject("actor collision")
    log_actor = registry.get("external_log")
    if (
        type(log_actor) is not dict
        or set(log_actor) != set(rc["external_log_exact_fields"])
        or re.fullmatch(r"log_[0-9a-f]{24}", log_actor.get("opaque_log_id", ""))
        is None
        or log_actor.get("public_key_fingerprint_sha256") != identities["log"][0]
        or log_actor.get("key_purpose") != rc["external_log_key_purpose"]
        or any(
            HEX.fullmatch(log_actor.get(field, "")) is None
            for field in (
                "organization_commitment_sha256",
                "public_key_fingerprint_sha256",
                "sponsor_review_receipt_sha256",
            )
        )
        or log_actor["organization_commitment_sha256"]
        in {actor["organization_commitment_sha256"] for actor in actors}
        or log_actor["sponsor_review_receipt_sha256"]
        in {actor["sponsor_review_receipt_sha256"] for actor in actors}
    ):
        raise IndependentProvenanceV2Reject("log actor")
    signed(
        key_paths["sponsor"],
        provenance_names["trust_registry.v2.sig"],
        provenance_names["trust_registry.v2.json"],
    )
    boundary = documents["boundary"]
    bc = protocol["candidate_boundary_contract"]
    if (
        set(boundary) != set(bc["exact_fields"])
        or boundary.get("version") != bc["version"]
        or boundary.get("matcher_released") is not False
        or boundary.get("candidate_team_roster_root_sha256") != roster_digest
        or any(
            boundary.get(field) != expected
            for field, expected in protocol["candidate_snapshot_contract"].items()
        )
        or HEX.fullmatch(boundary.get("matcher_release_policy_sha256", ""))
        is None
    ):
        raise IndependentProvenanceV2Reject("candidate boundary")
    signed(
        key_paths["sponsor"],
        provenance_names["candidate_boundary.v2.sig"],
        provenance_names["candidate_boundary.v2.json"],
    )
    statement = documents["statement"]
    sc = protocol["provenance_statement_contract"]
    choice_root = compute_choices(manifest["sources"], protocol)
    if (
        set(statement) != set(sc["exact_fields"])
        or statement.get("version") != sc["version"]
        or re.fullmatch(r"att_[0-9a-f]{32}", statement.get("attestation_id", ""))
        is None
        or statement.get("corpus_id") != bundle_result["corpus_id"]
        or statement.get("public_manifest_sha256") != digest(manifest_path.read_bytes())
        or statement.get("payload_ciphertext_sha256") != bundle_result["payload_sha256"]
        or statement.get("source_choice_set_root_sha256") != choice_root
        or statement.get("source_count") != 4
        or statement.get("trust_registry_sha256")
        != digest(provenance_names["trust_registry.v2.json"].read_bytes())
        or statement.get("candidate_boundary_sha256")
        != digest(provenance_names["candidate_boundary.v2.json"].read_bytes())
        or HEX.fullmatch(statement.get("selection_log_commitment_sha256", ""))
        is None
        or statement.get("statements") != sc["statements_exact"]
        or statement.get("claim_boundary") != sc["claim_boundary_exact"]
    ):
        raise IndependentProvenanceV2Reject("statement")
    signed(
        key_paths["curator"],
        provenance_names["curator_statement.sig"],
        provenance_names["provenance_statement.v2.json"],
    )
    signed(
        key_paths["reviewer"],
        provenance_names["reviewer_statement.sig"],
        provenance_names["provenance_statement.v2.json"],
    )
    log_entry = documents["log"]
    lc = protocol["external_log_contract"]
    if (
        set(log_entry) != set(lc["exact_fields"])
        or log_entry.get("version") != lc["version"]
        or log_entry.get("opaque_log_id") != log_actor["opaque_log_id"]
        or type(log_entry.get("sequence_number")) is not int
        or log_entry["sequence_number"] < lc["sequence_number_minimum"]
        or HEX.fullmatch(log_entry.get("previous_checkpoint_sha256", "")) is None
        or log_entry.get("provenance_statement_sha256")
        != digest(provenance_names["provenance_statement.v2.json"].read_bytes())
        or log_entry.get("selection_log_commitment_sha256")
        != statement["selection_log_commitment_sha256"]
        or log_entry.get("source_choice_set_root_sha256") != choice_root
    ):
        raise IndependentProvenanceV2Reject("log entry")
    signed(
        key_paths["log"],
        provenance_names["external_log_entry.v2.sig"],
        provenance_names["external_log_entry.v2.json"],
    )
    times = [
        moment(registry["enrolled_utc"]),
        moment(boundary["snapshot_created_utc"]),
        moment(statement["choices_finalized_utc"]),
        moment(statement["issued_utc"]),
        moment(log_entry["integrated_utc"]),
    ]
    if times != sorted(times):
        raise IndependentProvenanceV2Reject("chronology")
    return {
        "status": protocol["decision_rule"]["mechanism_complete_label"],
        "corpus_id": statement["corpus_id"],
        "source_count": 4,
        "candidate_roster_members": len(roster),
        "candidate_roster_root_sha256": roster_digest,
        "source_choice_set_root_sha256": choice_root,
        "sponsor_key_fingerprint_sha256": identities["sponsor"][0],
        "curator_key_fingerprint_sha256": identities["curator"][0],
        "reviewer_key_fingerprint_sha256": identities["reviewer"][0],
        "external_log_key_fingerprint_sha256": identities["log"][0],
        "minimum_key_bits": min(value[1] for value in identities.values()),
        "signatures_verified": 4,
        "roster_nonmembership_checks": 2,
        "chronology_relations_verified": 4,
        "matcher_released": False,
        "social_independence_cryptographically_proved": False,
        "payload_decrypted": False,
    }


def inspect(
    trust_root: pathlib.Path,
    provenance: pathlib.Path,
    bundle: pathlib.Path,
    protocol: dict[str, Any],
    intake_protocol: dict[str, Any],
) -> dict[str, Any]:
    trust = trust_root / protocol["required_trust_root_files"][0]
    if not trust.exists():
        unexpected = {
            path.name for path in trust_root.iterdir() if path.name != "README.md"
        }
        if unexpected:
            raise IndependentProvenanceV2Reject("trust-root extras")
        return {
            "status": "WAITING_EXTERNAL_SPONSOR_TRUST_ROOT",
            "trust_root_present": False,
            "bundle_files_present": 0,
            "provenance_files_present": 0,
            "payload_decrypted": False,
        }
    bundle_required = set(intake_protocol["required_files"])
    bundle_names = {path.name for path in bundle.iterdir()}
    bundle_count = len(bundle_required & bundle_names)
    if bundle_count != len(bundle_required):
        return {
            "status": "WAITING_VALIDATION_V7_V2_BUNDLE",
            "trust_root_present": True,
            "bundle_files_present": bundle_count,
            "provenance_files_present": 0,
            "payload_decrypted": False,
        }
    required = set(protocol["required_provenance_files"])
    names = {path.name for path in provenance.iterdir()}
    count = len(required & names)
    if count != len(required):
        if names - required - {"README.md"}:
            raise IndependentProvenanceV2Reject("provenance extras")
        return {
            "status": "WAITING_ACCOUNTABLE_PROVENANCE_V2",
            "trust_root_present": True,
            "bundle_files_present": bundle_count,
            "provenance_files_present": count,
            "payload_decrypted": False,
        }
    return verify_complete(
        trust_root, provenance, bundle, protocol, intake_protocol
    )
