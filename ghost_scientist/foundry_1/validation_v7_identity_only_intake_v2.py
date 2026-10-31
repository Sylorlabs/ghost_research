#!/usr/bin/env python3
"""Primary validator for corrected validation-v7 identity intake v2."""

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


class V7V2Reject(ValueError):
    pass


HEX = re.compile(r"^[0-9a-f]{64}$")
CORPUS = re.compile(r"^v7-[0-9a-f]{32}$")
UTC = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
OPAQUE = re.compile(r"^src_[0-9a-f]{24}$")


def canonical(value: object) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n"
    ).encode()


def command(arguments: list[str]) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["openssl", *arguments],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def entropy(raw: bytes) -> float:
    counts = Counter(raw)
    size = len(raw)
    return (
        -sum((count / size) * math.log2(count / size) for count in counts.values())
        if size
        else 0.0
    )


def validate_complete(
    inbox: pathlib.Path, protocol: dict[str, Any]
) -> dict[str, Any]:
    required = set(protocol["required_files"])
    entries = {path.name: path for path in inbox.iterdir()}
    if set(entries) - required - {"README.md"}:
        raise V7V2Reject("unknown file")
    if required - set(entries):
        raise V7V2Reject("missing file")
    if any(path.is_symlink() or not path.is_file() for path in entries.values()):
        raise V7V2Reject("non-regular entry")
    if any(
        b"PRIVATE KEY" in path.read_bytes()
        for name, path in entries.items()
        if name.endswith(".pem")
    ):
        raise V7V2Reject("private key")
    manifest_path = entries["public_manifest.v2.json"]
    raw = manifest_path.read_bytes()
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as error:
        raise V7V2Reject("manifest JSON") from error
    contract = protocol["public_manifest_contract"]
    if (
        not isinstance(value, dict)
        or raw != canonical(value)
        or set(value) != set(contract["exact_top_level_fields"])
        or value.get("version") != contract["version"]
        or CORPUS.fullmatch(value.get("corpus_id", "")) is None
        or UTC.fullmatch(value.get("created_utc", "")) is None
        or HEX.fullmatch(value.get("curator_key_fingerprint_sha256", ""))
        is None
        or value.get("selection_attestation")
        != contract["selection_attestation_exact"]
    ):
        raise V7V2Reject("manifest contract")
    rows = value.get("sources")
    fields = set(contract["source_exact_fields"])
    if not isinstance(rows, list) or len(rows) != contract["sources"]:
        raise V7V2Reject("source count")
    if "source_tree_sha256" in fields:
        raise V7V2Reject("raw source-tree digest contract")
    for row in rows:
        if not isinstance(row, dict) or set(row) != fields:
            raise V7V2Reject("source fields")
        if OPAQUE.fullmatch(row.get("opaque_source_id", "")) is None:
            raise V7V2Reject("opaque source id")
        if any(
            HEX.fullmatch(row.get(field, "")) is None
            for field in fields - {"opaque_source_id"}
        ):
            raise V7V2Reject("source commitment")
    if any(len({row[field] for row in rows}) != len(rows) for field in fields):
        raise V7V2Reject("duplicate source commitment")
    payload_record = value.get("payload")
    payload_fields = set(contract["payload_exact_fields"])
    if (
        not isinstance(payload_record, dict)
        or set(payload_record) != payload_fields
        or payload_record.get("encryption") != contract["encryption"]
        or type(payload_record.get("ciphertext_bytes")) is not int
        or payload_record["ciphertext_bytes"] < contract["minimum_ciphertext_bytes"]
        or HEX.fullmatch(payload_record.get("ciphertext_sha256", "")) is None
        or HEX.fullmatch(
            payload_record.get("plaintext_tree_commitment_sha256", "")
        )
        is None
    ):
        raise V7V2Reject("payload record")
    try:
        nonce = base64.b64decode(payload_record["nonce_base64"], validate=True)
        tag = base64.b64decode(
            payload_record["authentication_tag_base64"], validate=True
        )
    except (TypeError, ValueError):
        raise V7V2Reject("payload base64") from None
    if len(nonce) != 12 or len(tag) != 16:
        raise V7V2Reject("AEAD lengths")
    key = entries["curator_public_key.pem"]
    parsed = command(["pkey", "-pubin", "-in", str(key), "-text", "-noout"])
    match = re.search(rb"Public-Key: \((\d+) bit\)", parsed.stdout)
    if parsed.returncode or match is None or int(match.group(1)) < 3072:
        raise V7V2Reject("public key")
    der = command(["pkey", "-pubin", "-in", str(key), "-outform", "DER"])
    fingerprint = hashlib.sha256(der.stdout).hexdigest()
    if (
        der.returncode
        or fingerprint != value["curator_key_fingerprint_sha256"]
    ):
        raise V7V2Reject("key fingerprint")
    verified = command(
        [
            "dgst",
            "-sha256",
            "-verify",
            str(key),
            "-signature",
            str(entries["public_manifest.v2.sig"]),
            "-sigopt",
            "rsa_padding_mode:pss",
            "-sigopt",
            "rsa_pss_saltlen:digest",
            str(manifest_path),
        ]
    )
    if verified.returncode:
        raise V7V2Reject("signature")
    payload = entries["payload.v7.enc"].read_bytes()
    payload_sha = hashlib.sha256(payload).hexdigest()
    if (
        len(payload) != payload_record["ciphertext_bytes"]
        or payload_sha != payload_record["ciphertext_sha256"]
        or entries["payload.v7.sha256"].read_bytes()
        != f"{payload_sha}  payload.v7.enc\n".encode()
        or entropy(payload)
        < contract["minimum_observed_ciphertext_entropy_bits_per_byte"]
    ):
        raise V7V2Reject("ciphertext")
    return {
        "status": "VALIDATION_V7_IDENTITY_ONLY_INTAKE_V2_COMPLETE",
        "corpus_id": value["corpus_id"],
        "sources": len(rows),
        "manifest_sha256": hashlib.sha256(raw).hexdigest(),
        "payload_sha256": payload_sha,
        "payload_bytes": len(payload),
        "payload_entropy_bits_per_byte": entropy(payload),
        "curator_key_fingerprint_sha256": fingerprint,
        "curator_key_bits": int(match.group(1)),
        "manifest_signature_verified": True,
        "source_tree_commitment_field_present": True,
        "raw_source_tree_digest_field_present": False,
        "payload_decrypted": False,
    }


def inspect_inbox(
    inbox: pathlib.Path, protocol: dict[str, Any]
) -> dict[str, Any]:
    required = set(protocol["required_files"])
    if not inbox.is_dir():
        names: set[str] = set()
    else:
        paths = list(inbox.iterdir())
        names = {path.name for path in paths}
        if names - required - {"README.md"}:
            raise V7V2Reject("unknown file while waiting")
        if any(path.is_symlink() or not path.is_file() for path in paths):
            raise V7V2Reject("non-regular entry while waiting")
    present = sorted(required & names)
    if len(present) != len(required):
        return {
            "status": "VALIDATION_V7_IDENTITY_ONLY_INTAKE_V2_WAITING",
            "present_required_files": present,
            "missing_required_files": sorted(required - names),
            "payload_decrypted": False,
        }
    return validate_complete(inbox, protocol)
