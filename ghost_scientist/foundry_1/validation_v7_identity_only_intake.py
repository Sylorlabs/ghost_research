#!/usr/bin/env python3
"""Primary validator for the validation-v7 identity-only sealed inbox."""

from __future__ import annotations

import base64
import hashlib
import json
import math
import pathlib
import re
import subprocess
from collections import Counter
from typing import Any


class V7IntakeReject(ValueError):
    pass


HEX = re.compile(r"^[0-9a-f]{64}$")
CORPUS = re.compile(r"^v7-[0-9a-f]{32}$")
UTC = re.compile(
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
)
OPAQUE = re.compile(r"^src_[0-9a-f]{24}$")


def canonical(value: object) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n"
    ).encode()


def file_sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def entropy(data: bytes) -> float:
    if not data:
        return 0.0
    counts = Counter(data)
    size = len(data)
    return -sum(
        (count / size) * math.log2(count / size)
        for count in counts.values()
    )


def openssl(
    arguments: list[str], *, input_bytes: bytes | None = None
) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["openssl", *arguments],
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def public_key_fingerprint(path: pathlib.Path) -> tuple[str, int]:
    if b"PRIVATE KEY" in path.read_bytes():
        raise V7IntakeReject("private key material in public key file")
    text = openssl(["pkey", "-pubin", "-in", str(path), "-text", "-noout"])
    if text.returncode != 0:
        raise V7IntakeReject("public key parse")
    match = re.search(rb"Public-Key: \(([0-9]+) bit\)", text.stdout)
    if match is None:
        raise V7IntakeReject("public key bit length")
    bits = int(match.group(1))
    if bits < 3072:
        raise V7IntakeReject("public key too small")
    der = openssl(
        ["pkey", "-pubin", "-in", str(path), "-outform", "DER"]
    )
    if der.returncode != 0:
        raise V7IntakeReject("public key DER")
    return hashlib.sha256(der.stdout).hexdigest(), bits


def validate_manifest(
    value: dict[str, Any], protocol: dict[str, Any]
) -> None:
    contract = protocol["public_manifest_contract"]
    if set(value) != set(contract["exact_top_level_fields"]):
        raise V7IntakeReject("manifest fields")
    if (
        value["version"] != contract["version"]
        or not isinstance(value["corpus_id"], str)
        or CORPUS.fullmatch(value["corpus_id"]) is None
        or not isinstance(value["created_utc"], str)
        or UTC.fullmatch(value["created_utc"]) is None
        or not isinstance(value["curator_key_fingerprint_sha256"], str)
        or HEX.fullmatch(value["curator_key_fingerprint_sha256"]) is None
    ):
        raise V7IntakeReject("manifest identity")
    expected_attestation = contract["selection_attestation_exact"]
    if value["selection_attestation"] != expected_attestation:
        raise V7IntakeReject("selection attestation")
    sources = value["sources"]
    source_fields = set(contract["source_exact_fields"])
    if not isinstance(sources, list) or len(sources) != contract["sources"]:
        raise V7IntakeReject("source cardinality")
    for row in sources:
        if not isinstance(row, dict) or set(row) != source_fields:
            raise V7IntakeReject("source fields")
        if (
            not isinstance(row["opaque_source_id"], str)
            or OPAQUE.fullmatch(row["opaque_source_id"]) is None
        ):
            raise V7IntakeReject("opaque source id")
        for field in source_fields - {"opaque_source_id"}:
            if (
                not isinstance(row[field], str)
                or HEX.fullmatch(row[field]) is None
            ):
                raise V7IntakeReject(f"source commitment {field}")
    for field in source_fields:
        values = [row[field] for row in sources]
        if len(set(values)) != len(values):
            raise V7IntakeReject(f"duplicate source field {field}")
    payload = value["payload"]
    if (
        not isinstance(payload, dict)
        or set(payload) != set(contract["payload_exact_fields"])
        or payload["encryption"] != contract["encryption"]
        or not isinstance(payload["ciphertext_bytes"], int)
        or isinstance(payload["ciphertext_bytes"], bool)
        or payload["ciphertext_bytes"]
        < contract["minimum_ciphertext_bytes"]
    ):
        raise V7IntakeReject("payload schema")
    for field in ("ciphertext_sha256", "plaintext_tree_sha256"):
        if (
            not isinstance(payload[field], str)
            or HEX.fullmatch(payload[field]) is None
        ):
            raise V7IntakeReject(f"payload digest {field}")
    try:
        nonce = base64.b64decode(payload["nonce_base64"], validate=True)
        tag = base64.b64decode(
            payload["authentication_tag_base64"], validate=True
        )
    except (ValueError, TypeError):
        raise V7IntakeReject("payload base64") from None
    if len(nonce) != 12 or len(tag) != 16:
        raise V7IntakeReject("payload nonce or tag length")


def validate_complete(
    inbox: pathlib.Path, protocol: dict[str, Any]
) -> dict[str, Any]:
    required = set(protocol["required_files"])
    allowed = required | {"README.md"}
    if not inbox.is_dir():
        raise V7IntakeReject("inbox absent")
    entries = list(inbox.iterdir())
    names = {path.name for path in entries}
    if names - allowed:
        raise V7IntakeReject("unknown inbox file")
    if required - names:
        raise V7IntakeReject("missing required file")
    if any(path.is_symlink() or not path.is_file() for path in entries):
        raise V7IntakeReject("non-regular inbox entry")
    forbidden_names = [
        name
        for name in names
        if (
            name not in required
            and name != "README.md"
            and pathlib.Path(name).suffix.lower()
            in {".py", ".jsonl", ".tar", ".zip", ".key", ".src"}
        )
    ]
    if forbidden_names:
        raise V7IntakeReject("plaintext-like or key file")
    manifest_path = inbox / "public_manifest.v1.json"
    raw_manifest = manifest_path.read_bytes()
    try:
        manifest = json.loads(raw_manifest)
    except json.JSONDecodeError as error:
        raise V7IntakeReject("manifest JSON") from error
    if not isinstance(manifest, dict) or raw_manifest != canonical(manifest):
        raise V7IntakeReject("manifest not canonical")
    validate_manifest(manifest, protocol)
    key_path = inbox / "curator_public_key.pem"
    fingerprint, key_bits = public_key_fingerprint(key_path)
    if fingerprint != manifest["curator_key_fingerprint_sha256"]:
        raise V7IntakeReject("curator fingerprint mismatch")
    signature = inbox / "public_manifest.v1.sig"
    verified = openssl(
        [
            "dgst",
            "-sha256",
            "-verify",
            str(key_path),
            "-signature",
            str(signature),
            "-sigopt",
            "rsa_padding_mode:pss",
            "-sigopt",
            "rsa_pss_saltlen:digest",
            str(manifest_path),
        ]
    )
    if verified.returncode != 0:
        raise V7IntakeReject("manifest signature mismatch")
    payload_path = inbox / "payload.v7.enc"
    payload = payload_path.read_bytes()
    payload_record = manifest["payload"]
    digest = hashlib.sha256(payload).hexdigest()
    if (
        len(payload) != payload_record["ciphertext_bytes"]
        or digest != payload_record["ciphertext_sha256"]
    ):
        raise V7IntakeReject("ciphertext relation")
    sidecar = (inbox / "payload.v7.sha256").read_bytes()
    expected_sidecar = f"{digest}  payload.v7.enc\n".encode()
    if sidecar != expected_sidecar:
        raise V7IntakeReject("payload digest sidecar")
    observed_entropy = entropy(payload)
    if (
        observed_entropy
        < protocol["public_manifest_contract"][
            "minimum_observed_ciphertext_entropy_bits_per_byte"
        ]
    ):
        raise V7IntakeReject("ciphertext entropy")
    return {
        "status": "VALIDATION_V7_IDENTITY_ONLY_INTAKE_COMPLETE",
        "corpus_id": manifest["corpus_id"],
        "sources": len(manifest["sources"]),
        "distinct_repository_commitments": len(
            {
                row["repository_commitment_sha256"]
                for row in manifest["sources"]
            }
        ),
        "distinct_semantic_domain_commitments": len(
            {
                row["semantic_domain_commitment_sha256"]
                for row in manifest["sources"]
            }
        ),
        "manifest_sha256": hashlib.sha256(raw_manifest).hexdigest(),
        "payload_sha256": digest,
        "payload_bytes": len(payload),
        "payload_entropy_bits_per_byte": observed_entropy,
        "curator_key_fingerprint_sha256": fingerprint,
        "curator_key_bits": key_bits,
        "manifest_signature_verified": True,
        "payload_decrypted": False,
    }


def inspect_inbox(
    inbox: pathlib.Path, protocol: dict[str, Any]
) -> dict[str, Any]:
    required = set(protocol["required_files"])
    allowed = required | {"README.md"}
    if not inbox.exists():
        return {
            "status": "VALIDATION_V7_IDENTITY_ONLY_INTAKE_WAITING",
            "present_required_files": [],
            "missing_required_files": sorted(required),
            "payload_decrypted": False,
        }
    entries = list(inbox.iterdir())
    names = {path.name for path in entries}
    if names - allowed or any(
        path.is_symlink() or not path.is_file() for path in entries
    ):
        raise V7IntakeReject("unsafe or unknown inbox entry")
    missing = sorted(required - names)
    if missing:
        return {
            "status": "VALIDATION_V7_IDENTITY_ONLY_INTAKE_WAITING",
            "present_required_files": sorted(required & names),
            "missing_required_files": missing,
            "payload_decrypted": False,
        }
    return validate_complete(inbox, protocol)
