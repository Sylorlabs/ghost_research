#!/usr/bin/env python3
"""Independent validator for corrected validation-v7 intake v2."""

from __future__ import annotations

import base64
import hashlib
import json
import math
import pathlib
import re
import subprocess
from typing import Any


class IndependentV7V2Reject(ValueError):
    pass


def encode(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode() + b"\n"


def openssl(args: list[str]) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["openssl", *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def shannon(raw: bytes) -> float:
    if not raw:
        return 0.0
    size = len(raw)
    return -sum(
        (raw.count(bytes([byte])) / size)
        * math.log2(raw.count(bytes([byte])) / size)
        for byte in set(raw)
    )


def verify_complete(
    directory: pathlib.Path, protocol: dict[str, Any]
) -> dict[str, Any]:
    paths = {item.name: item for item in directory.iterdir()}
    required = set(protocol["required_files"])
    if set(paths) - required - {"README.md"} or not required <= set(paths):
        raise IndependentV7V2Reject("file set")
    if any(item.is_symlink() or not item.is_file() for item in paths.values()):
        raise IndependentV7V2Reject("entry type")
    if b"PRIVATE KEY" in paths["curator_public_key.pem"].read_bytes():
        raise IndependentV7V2Reject("private key")
    raw = paths["public_manifest.v2.json"].read_bytes()
    try:
        manifest = json.loads(raw)
    except json.JSONDecodeError as error:
        raise IndependentV7V2Reject("JSON") from error
    contract = protocol["public_manifest_contract"]
    if (
        raw != encode(manifest)
        or not isinstance(manifest, dict)
        or sorted(manifest) != sorted(contract["exact_top_level_fields"])
        or manifest.get("version") != contract["version"]
        or re.fullmatch(r"v7-[0-9a-f]{32}", manifest.get("corpus_id", ""))
        is None
        or re.fullmatch(
            r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z",
            manifest.get("created_utc", ""),
        )
        is None
        or manifest.get("selection_attestation")
        != contract["selection_attestation_exact"]
    ):
        raise IndependentV7V2Reject("manifest")
    fields = set(contract["source_exact_fields"])
    rows = manifest.get("sources")
    if (
        "source_tree_commitment_sha256" not in fields
        or "source_tree_sha256" in fields
        or not isinstance(rows, list)
        or len(rows) != 4
    ):
        raise IndependentV7V2Reject("source contract")
    hex64 = re.compile(r"[0-9a-f]{64}")
    for row in rows:
        if (
            not isinstance(row, dict)
            or set(row) != fields
            or re.fullmatch(r"src_[0-9a-f]{24}", row.get("opaque_source_id", ""))
            is None
            or any(
                hex64.fullmatch(row.get(field, "")) is None
                for field in fields - {"opaque_source_id"}
            )
        ):
            raise IndependentV7V2Reject("source")
    for field in fields:
        if len({row[field] for row in rows}) != 4:
            raise IndependentV7V2Reject("source duplicate")
    record = manifest.get("payload")
    if (
        not isinstance(record, dict)
        or set(record) != set(contract["payload_exact_fields"])
        or record.get("encryption") != "AES-256-GCM"
        or type(record.get("ciphertext_bytes")) is not int
        or record["ciphertext_bytes"] < contract["minimum_ciphertext_bytes"]
        or hex64.fullmatch(record.get("ciphertext_sha256", "")) is None
        or hex64.fullmatch(record.get("plaintext_tree_commitment_sha256", ""))
        is None
    ):
        raise IndependentV7V2Reject("payload")
    try:
        nonce = base64.b64decode(record["nonce_base64"], validate=True)
        tag = base64.b64decode(record["authentication_tag_base64"], validate=True)
    except (TypeError, ValueError):
        raise IndependentV7V2Reject("base64") from None
    if (len(nonce), len(tag)) != (12, 16):
        raise IndependentV7V2Reject("AEAD")
    key = paths["curator_public_key.pem"]
    info = openssl(["pkey", "-pubin", "-in", str(key), "-text", "-noout"])
    bits = re.search(rb"Public-Key: \((\d+) bit\)", info.stdout)
    der = openssl(["pkey", "-pubin", "-in", str(key), "-outform", "DER"])
    fingerprint = hashlib.sha256(der.stdout).hexdigest()
    if (
        info.returncode
        or der.returncode
        or bits is None
        or int(bits.group(1)) < 3072
        or fingerprint != manifest.get("curator_key_fingerprint_sha256")
    ):
        raise IndependentV7V2Reject("key")
    signature = openssl(
        [
            "dgst",
            "-sha256",
            "-verify",
            str(key),
            "-signature",
            str(paths["public_manifest.v2.sig"]),
            "-sigopt",
            "rsa_padding_mode:pss",
            "-sigopt",
            "rsa_pss_saltlen:digest",
            str(paths["public_manifest.v2.json"]),
        ]
    )
    if signature.returncode:
        raise IndependentV7V2Reject("signature")
    payload = paths["payload.v7.enc"].read_bytes()
    digest = hashlib.sha256(payload).hexdigest()
    entropy = shannon(payload)
    if (
        len(payload) != record["ciphertext_bytes"]
        or digest != record["ciphertext_sha256"]
        or paths["payload.v7.sha256"].read_bytes()
        != f"{digest}  payload.v7.enc\n".encode()
        or entropy < contract["minimum_observed_ciphertext_entropy_bits_per_byte"]
    ):
        raise IndependentV7V2Reject("ciphertext")
    return {
        "status": "VALIDATION_V7_IDENTITY_ONLY_INTAKE_V2_COMPLETE",
        "corpus_id": manifest["corpus_id"],
        "sources": 4,
        "manifest_sha256": hashlib.sha256(raw).hexdigest(),
        "payload_sha256": digest,
        "payload_bytes": len(payload),
        "payload_entropy_bits_per_byte": entropy,
        "curator_key_fingerprint_sha256": fingerprint,
        "curator_key_bits": int(bits.group(1)),
        "manifest_signature_verified": True,
        "source_tree_commitment_field_present": True,
        "raw_source_tree_digest_field_present": False,
        "payload_decrypted": False,
    }


def inspect(
    directory: pathlib.Path, protocol: dict[str, Any]
) -> dict[str, Any]:
    required = set(protocol["required_files"])
    names = {item.name for item in directory.iterdir()} if directory.exists() else set()
    if names - required - {"README.md"}:
        raise IndependentV7V2Reject("unexpected waiting file")
    present = sorted(required & names)
    if len(present) != len(required):
        return {
            "status": "VALIDATION_V7_IDENTITY_ONLY_INTAKE_V2_WAITING",
            "present_required_files": present,
            "missing_required_files": sorted(required - names),
            "payload_decrypted": False,
        }
    return verify_complete(directory, protocol)
