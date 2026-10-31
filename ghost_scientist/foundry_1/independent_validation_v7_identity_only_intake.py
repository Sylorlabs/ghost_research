#!/usr/bin/env python3
"""Independent validator for the opaque validation-v7 intake."""

from __future__ import annotations

import base64
import hashlib
import json
import math
import pathlib
import re
import subprocess
from typing import Any


class IndependentV7Reject(ValueError):
    pass


HEX = re.compile("[0-9a-f]{64}")


def encode(value: object) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":")
    ).encode() + b"\n"


def shannon(data: bytes) -> float:
    if not data:
        return 0.0
    return -sum(
        (data.count(bytes([item])) / len(data))
        * math.log2(data.count(bytes([item])) / len(data))
        for item in set(data)
    )


def command(arguments: list[str]) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["openssl", *arguments],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def verify_complete(
    directory: pathlib.Path, protocol: dict[str, Any]
) -> dict[str, Any]:
    required = set(protocol["required_files"])
    paths = {item.name: item for item in directory.iterdir()}
    if set(paths) - required - {"README.md"}:
        raise IndependentV7Reject("unexpected entry")
    if not required <= set(paths):
        raise IndependentV7Reject("incomplete")
    if any(item.is_symlink() or not item.is_file() for item in paths.values()):
        raise IndependentV7Reject("entry type")
    raw = paths["public_manifest.v1.json"].read_bytes()
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as error:
        raise IndependentV7Reject("JSON") from error
    contract = protocol["public_manifest_contract"]
    if (
        raw != encode(value)
        or not isinstance(value, dict)
        or sorted(value) != sorted(contract["exact_top_level_fields"])
        or value.get("version") != contract["version"]
        or re.fullmatch(r"v7-[0-9a-f]{32}", value.get("corpus_id", ""))
        is None
        or re.fullmatch(
            r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z",
            value.get("created_utc", ""),
        )
        is None
        or value.get("selection_attestation")
        != contract["selection_attestation_exact"]
    ):
        raise IndependentV7Reject("manifest")
    rows = value.get("sources")
    fields = set(contract["source_exact_fields"])
    if not isinstance(rows, list) or len(rows) != 4:
        raise IndependentV7Reject("sources")
    for row in rows:
        if not isinstance(row, dict) or set(row) != fields:
            raise IndependentV7Reject("source keys")
        if re.fullmatch(r"src_[0-9a-f]{24}", row["opaque_source_id"]) is None:
            raise IndependentV7Reject("opaque id")
        if any(
            HEX.fullmatch(row[field]) is None
            for field in fields - {"opaque_source_id"}
        ):
            raise IndependentV7Reject("commitment")
    if any(
        len({row[field] for row in rows}) != len(rows) for field in fields
    ):
        raise IndependentV7Reject("duplicate source value")
    payload_record = value.get("payload")
    if (
        not isinstance(payload_record, dict)
        or set(payload_record) != set(contract["payload_exact_fields"])
        or payload_record.get("encryption") != "AES-256-GCM"
        or type(payload_record.get("ciphertext_bytes")) is not int
        or payload_record["ciphertext_bytes"]
        < contract["minimum_ciphertext_bytes"]
        or HEX.fullmatch(payload_record.get("ciphertext_sha256", "")) is None
        or HEX.fullmatch(payload_record.get("plaintext_tree_sha256", ""))
        is None
    ):
        raise IndependentV7Reject("payload record")
    try:
        nonce = base64.b64decode(
            payload_record["nonce_base64"], validate=True
        )
        tag = base64.b64decode(
            payload_record["authentication_tag_base64"], validate=True
        )
    except (ValueError, TypeError):
        raise IndependentV7Reject("base64") from None
    if len(nonce) != 12 or len(tag) != 16:
        raise IndependentV7Reject("AEAD fields")
    key = paths["curator_public_key.pem"]
    key_bytes = key.read_bytes()
    if b"PRIVATE KEY" in key_bytes:
        raise IndependentV7Reject("private key")
    text = command(["pkey", "-pubin", "-in", str(key), "-text", "-noout"])
    match = re.search(rb"Public-Key: \(([0-9]+) bit\)", text.stdout)
    if text.returncode or match is None or int(match.group(1)) < 3072:
        raise IndependentV7Reject("RSA key")
    der = command(["pkey", "-pubin", "-in", str(key), "-outform", "DER"])
    fingerprint = hashlib.sha256(der.stdout).hexdigest()
    if (
        der.returncode
        or fingerprint != value["curator_key_fingerprint_sha256"]
    ):
        raise IndependentV7Reject("fingerprint")
    signature = command(
        [
            "dgst",
            "-sha256",
            "-verify",
            str(key),
            "-signature",
            str(paths["public_manifest.v1.sig"]),
            "-sigopt",
            "rsa_padding_mode:pss",
            "-sigopt",
            "rsa_pss_saltlen:digest",
            str(paths["public_manifest.v1.json"]),
        ]
    )
    if signature.returncode:
        raise IndependentV7Reject("signature")
    payload = paths["payload.v7.enc"].read_bytes()
    digest = hashlib.sha256(payload).hexdigest()
    if (
        len(payload) != payload_record["ciphertext_bytes"]
        or digest != payload_record["ciphertext_sha256"]
        or paths["payload.v7.sha256"].read_bytes()
        != f"{digest}  payload.v7.enc\n".encode()
        or shannon(payload)
        < contract["minimum_observed_ciphertext_entropy_bits_per_byte"]
    ):
        raise IndependentV7Reject("ciphertext")
    return {
        "status": "VALIDATION_V7_IDENTITY_ONLY_INTAKE_COMPLETE",
        "corpus_id": value["corpus_id"],
        "sources": 4,
        "distinct_repository_commitments": len(
            {row["repository_commitment_sha256"] for row in rows}
        ),
        "distinct_semantic_domain_commitments": len(
            {row["semantic_domain_commitment_sha256"] for row in rows}
        ),
        "manifest_sha256": hashlib.sha256(raw).hexdigest(),
        "payload_sha256": digest,
        "payload_bytes": len(payload),
        "payload_entropy_bits_per_byte": shannon(payload),
        "curator_key_fingerprint_sha256": fingerprint,
        "curator_key_bits": int(match.group(1)),
        "manifest_signature_verified": True,
        "payload_decrypted": False,
    }


def inspect(
    directory: pathlib.Path, protocol: dict[str, Any]
) -> dict[str, Any]:
    required = set(protocol["required_files"])
    if not directory.exists():
        return {
            "status": "VALIDATION_V7_IDENTITY_ONLY_INTAKE_WAITING",
            "present_required_files": [],
            "missing_required_files": sorted(required),
            "payload_decrypted": False,
        }
    names = {item.name for item in directory.iterdir()}
    if names - required - {"README.md"}:
        raise IndependentV7Reject("unsafe entry")
    missing = sorted(required - names)
    if missing:
        return {
            "status": "VALIDATION_V7_IDENTITY_ONLY_INTAKE_WAITING",
            "present_required_files": sorted(required & names),
            "missing_required_files": missing,
            "payload_decrypted": False,
        }
    return verify_complete(directory, protocol)
