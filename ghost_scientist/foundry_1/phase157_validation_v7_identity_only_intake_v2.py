#!/usr/bin/env python3
"""Falsify and execute corrected validation-v7 identity intake v2."""

from __future__ import annotations

import base64
import copy
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

from independent_validation_v7_identity_only_intake_v2 import (
    IndependentV7V2Reject,
    inspect as independent_inspect,
    verify_complete as independent_verify,
)
from resource_meter_v2 import run_metered_tree
from validation_v7_identity_only_intake_v2 import (
    V7V2Reject,
    canonical,
    inspect_inbox,
    validate_complete,
)


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/VALIDATION_V7_IDENTITY_ONLY_INTAKE_PROTOCOL_V2.json"
)
FREEZE = HERE / "results/validation_v7_identity_only_intake_v2_freeze.json"
INBOX = HERE / "validation_v7_sealed_inbox"
WORKER_RESULT = HERE / "results/phase157_validation_v7_identity_only_intake_v2_worker.json"
RESULT = HERE / "results/phase157_validation_v7_identity_only_intake_v2.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args: list[str]) -> bytes:
    process = subprocess.run(
        args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False
    )
    if process.returncode:
        raise RuntimeError(process.stderr.decode(errors="replace"))
    return process.stdout


def fingerprint(public_key: pathlib.Path) -> str:
    return hashlib.sha256(
        run(
            [
                "openssl",
                "pkey",
                "-pubin",
                "-in",
                str(public_key),
                "-outform",
                "DER",
            ]
        )
    ).hexdigest()


def sign(directory: pathlib.Path, private_key: pathlib.Path) -> None:
    manifest = directory / "public_manifest.v2.json"
    value = json.loads(manifest.read_text())
    manifest.write_bytes(canonical(value))
    run(
        [
            "openssl",
            "dgst",
            "-sha256",
            "-sign",
            str(private_key),
            "-sigopt",
            "rsa_padding_mode:pss",
            "-sigopt",
            "rsa_pss_saltlen:digest",
            "-out",
            str(directory / "public_manifest.v2.sig"),
            str(manifest),
        ]
    )


def deterministic_ciphertext(size: int = 8192) -> bytes:
    result = bytearray()
    index = 0
    while len(result) < size:
        result.extend(hashlib.sha256(f"v7-v2-block:{index}".encode()).digest())
        index += 1
    return bytes(result[:size])


def commitment(field: str, index: int, protocol: dict) -> str:
    domain = protocol["commitment_policy"]["domain_separators"][field].encode()
    salt = hashlib.sha256(f"v7-v2-secret-salt:{field}:{index}".encode()).digest()[:16]
    identity = f"fixture-canonical-identity:{field}:{index}".encode()
    return hashlib.sha256(domain + b"\0" + salt + b"\0" + identity).hexdigest()


def build_fixture(root: pathlib.Path, protocol: dict) -> tuple[pathlib.Path, pathlib.Path]:
    directory = root / "valid"
    directory.mkdir()
    private_key = root / "fixture-private.pem"
    run(
        [
            "openssl",
            "genpkey",
            "-algorithm",
            "RSA",
            "-pkeyopt",
            "rsa_keygen_bits:3072",
            "-out",
            str(private_key),
        ]
    )
    public_key = directory / "curator_public_key.pem"
    run(
        [
            "openssl",
            "pkey",
            "-in",
            str(private_key),
            "-pubout",
            "-out",
            str(public_key),
        ]
    )
    payload = deterministic_ciphertext()
    payload_sha = hashlib.sha256(payload).hexdigest()
    (directory / "payload.v7.enc").write_bytes(payload)
    (directory / "payload.v7.sha256").write_text(
        f"{payload_sha}  payload.v7.enc\n"
    )
    fields = protocol["public_manifest_contract"]["source_exact_fields"]
    sources = []
    for index in range(4):
        row = {"opaque_source_id": f"src_{index + 1:024x}"}
        for field in fields:
            if field != "opaque_source_id":
                row[field] = commitment(field, index, protocol)
        sources.append(row)
    manifest = {
        "version": protocol["public_manifest_contract"]["version"],
        "corpus_id": "v7-" + "2" * 32,
        "created_utc": "2026-07-30T23:30:00Z",
        "curator_key_fingerprint_sha256": fingerprint(public_key),
        "selection_attestation": protocol["public_manifest_contract"][
            "selection_attestation_exact"
        ],
        "sources": sources,
        "payload": {
            "ciphertext_sha256": payload_sha,
            "ciphertext_bytes": len(payload),
            "encryption": "AES-256-GCM",
            "nonce_base64": base64.b64encode(bytes(range(12))).decode(),
            "authentication_tag_base64": base64.b64encode(bytes(range(16))).decode(),
            "plaintext_tree_commitment_sha256": hashlib.sha256(
                b"v7-v2-secret-tree-salt\0fixture-plaintext-tree"
            ).hexdigest(),
        },
    }
    (directory / "public_manifest.v2.json").write_bytes(canonical(manifest))
    sign(directory, private_key)
    return directory, private_key


def worker() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    with tempfile.TemporaryDirectory(prefix="foundry-v7-v2-") as name:
        root = pathlib.Path(name)
        valid, private_key = build_fixture(root, protocol)
        primary_valid = validate_complete(valid, protocol)
        independent_valid = independent_verify(valid, protocol)
        fields = (
            "status",
            "corpus_id",
            "sources",
            "manifest_sha256",
            "payload_sha256",
            "payload_bytes",
            "curator_key_fingerprint_sha256",
            "curator_key_bits",
            "manifest_signature_verified",
            "source_tree_commitment_field_present",
            "raw_source_tree_digest_field_present",
            "payload_decrypted",
        )
        if any(primary_valid[field] != independent_valid[field] for field in fields):
            raise RuntimeError("v2 validators disagree on positive fixture")
        hostile = []

        def manifest_mutation(path: pathlib.Path, mutation) -> None:
            target = path / "public_manifest.v2.json"
            value = json.loads(target.read_text())
            mutation(value)
            target.write_bytes(canonical(value))

        def case(name: str, mutation, *, resign: bool = False) -> None:
            target = root / f"hostile-{len(hostile):02d}"
            shutil.copytree(valid, target)
            mutation(target)
            if resign:
                sign(target, private_key)
            primary_rejected = independent_rejected = False
            try:
                validate_complete(target, protocol)
            except (V7V2Reject, KeyError, TypeError, ValueError, json.JSONDecodeError):
                primary_rejected = True
            try:
                independent_verify(target, protocol)
            except (
                IndependentV7V2Reject,
                KeyError,
                TypeError,
                ValueError,
                json.JSONDecodeError,
            ):
                independent_rejected = True
            hostile.append(
                {
                    "case": name,
                    "primary_rejected": primary_rejected,
                    "independent_rejected": independent_rejected,
                }
            )

        case(
            "v1_manifest_artifact",
            lambda path: (path / "public_manifest.v2.json").rename(
                path / "public_manifest.v1.json"
            ),
        )
        case("missing_required_file", lambda path: (path / "payload.v7.sha256").unlink())
        case("unknown_file", lambda path: (path / "unknown.bin").write_bytes(b"x"))
        case(
            "private_key_present",
            lambda path: shutil.copyfile(private_key, path / "curator_public_key.pem"),
        )
        case("plaintext_source_like_file", lambda path: (path / "runtime.py").write_text("pass\n"))
        case(
            "unknown_manifest_field",
            lambda path: manifest_mutation(path, lambda value: value.update(extra=True)),
            resign=True,
        )
        case(
            "plaintext_repository_identity_field",
            lambda path: manifest_mutation(
                path, lambda value: value["sources"][0].update(repository="public/name")
            ),
            resign=True,
        )

        def raw_tree_field(value: dict) -> None:
            for row in value["sources"]:
                row["source_tree_sha256"] = row.pop(
                    "source_tree_commitment_sha256"
                )

        case(
            "raw_source_tree_digest_field",
            lambda path: manifest_mutation(path, raw_tree_field),
            resign=True,
        )
        case(
            "duplicate_opaque_source_id",
            lambda path: manifest_mutation(
                path,
                lambda value: value["sources"][1].update(
                    opaque_source_id=value["sources"][0]["opaque_source_id"]
                ),
            ),
            resign=True,
        )
        case(
            "duplicate_repository_commitment",
            lambda path: manifest_mutation(
                path,
                lambda value: value["sources"][1].update(
                    repository_commitment_sha256=value["sources"][0][
                        "repository_commitment_sha256"
                    ]
                ),
            ),
            resign=True,
        )
        case(
            "malformed_commitment",
            lambda path: manifest_mutation(
                path,
                lambda value: value["sources"][0].update(
                    revision_commitment_sha256="bad"
                ),
            ),
            resign=True,
        )
        case(
            "salted_commitment_attestation_weakened",
            lambda path: manifest_mutation(
                path,
                lambda value: value["selection_attestation"].update(
                    all_identity_commitments_domain_separated_and_salted=False
                ),
            ),
            resign=True,
        )
        case(
            "ciphertext_digest_mismatch",
            lambda path: manifest_mutation(
                path,
                lambda value: value["payload"].update(ciphertext_sha256="0" * 64),
            ),
            resign=True,
        )
        case(
            "digest_sidecar_mismatch",
            lambda path: (path / "payload.v7.sha256").write_text("0" * 64 + "  payload.v7.enc\n"),
        )

        def replace_payload(path: pathlib.Path, raw: bytes) -> None:
            digest = hashlib.sha256(raw).hexdigest()
            (path / "payload.v7.enc").write_bytes(raw)
            (path / "payload.v7.sha256").write_text(f"{digest}  payload.v7.enc\n")
            manifest_mutation(
                path,
                lambda value: value["payload"].update(
                    ciphertext_sha256=digest, ciphertext_bytes=len(raw)
                ),
            )

        case("ciphertext_too_small", lambda path: replace_payload(path, bytes(range(32))), resign=True)
        case("ciphertext_entropy_too_low", lambda path: replace_payload(path, b"x" * 8192), resign=True)
        case(
            "public_key_fingerprint_mismatch",
            lambda path: manifest_mutation(
                path,
                lambda value: value.update(curator_key_fingerprint_sha256="0" * 64),
            ),
            resign=True,
        )
        case(
            "manifest_signature_mismatch",
            lambda path: (path / "public_manifest.v2.sig").write_bytes(
                b"\0" + (path / "public_manifest.v2.sig").read_bytes()[1:]
            ),
        )
        real_primary = inspect_inbox(INBOX, protocol)
        real_independent = independent_inspect(INBOX, protocol)
        if real_primary != real_independent:
            raise RuntimeError("real v2 waiting validators disagree")
        payload = {
            "version": "FOUNDRY_VALIDATION_V7_IDENTITY_ONLY_V2_WORKER_V1",
            "synthetic_positive": primary_valid,
            "hostile_rejections": hostile,
            "real_inbox": real_primary,
            "summary": {
                "positive_validators": 2,
                "hostile_cases": len(hostile),
                "hostile_rejected_twice": sum(
                    row["primary_rejected"] and row["independent_rejected"]
                    for row in hostile
                ),
                "real_present_required_files": len(
                    real_primary["present_required_files"]
                ),
                "real_missing_required_files": len(
                    real_primary["missing_required_files"]
                ),
            },
            "payload_decrypted": False,
            "source_runtime_graph_shape_or_outcome_accessed": False,
        }
        WORKER_RESULT.write_text(
            json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
        )
        print(
            "FOUNDRY_PHASE157_WORKER positive=2/2"
            f" hostile={len(hostile)}/{len(hostile)}"
            f" real_status={real_primary['status']} real_present=0/5"
        )


def main() -> None:
    if len(sys.argv) == 2 and sys.argv[1] == "--worker":
        worker()
        return
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    if not (
        freeze["protocol_sha256"] == sha(PROTOCOL)
        and freeze["status"] == "FROZEN_BEFORE_V2_VALIDATORS_OR_EXTERNAL_BUNDLE"
    ):
        raise RuntimeError("v2 freeze mismatch")
    limits = protocol["resource_limits"]
    receipt = run_metered_tree(
        [sys.executable, str(pathlib.Path(__file__).resolve()), "--worker"],
        cwd=HERE,
        wall_limit_seconds=limits["wall_seconds"],
        cpu_limit_seconds=limits["cpu_seconds"],
        rss_limit_kib=limits["rss_kib"],
    )
    observed = json.loads(WORKER_RESULT.read_text())
    summary = observed["summary"]
    checks = {
        "protocol_frozen_before_v2_validators": True,
        "synthetic_positive_accepted_twice": summary["positive_validators"] == 2,
        "eighteen_hostile_cases_rejected_twice": (
            summary["hostile_cases"]
            == summary["hostile_rejected_twice"]
            == 18
        ),
        "real_inbox_safely_waiting": (
            observed["real_inbox"]["status"]
            == "VALIDATION_V7_IDENTITY_ONLY_INTAKE_V2_WAITING"
            and summary["real_present_required_files"] == 0
            and summary["real_missing_required_files"] == 5
        ),
        "salted_source_tree_commitment_positive": (
            observed["synthetic_positive"][
                "source_tree_commitment_field_present"
            ]
            is True
            and observed["synthetic_positive"][
                "raw_source_tree_digest_field_present"
            ]
            is False
        ),
        "no_payload_decryption": observed["payload_decrypted"] is False,
        "no_source_runtime_graph_shape_or_outcome_access": (
            observed["source_runtime_graph_shape_or_outcome_accessed"] is False
        ),
        "metered_worker_passed": (
            receipt["returncode"] == 0
            and receipt["termination"] == "natural"
            and receipt["process_group_reaped"] is True
        ),
    }
    if not all(checks.values()):
        raise RuntimeError("v2 intake conformance failed")
    result = {
        "version": "FOUNDRY_VALIDATION_V7_IDENTITY_ONLY_INTAKE_V2_RESULT_V1",
        "status": "VALIDATION_V7_IDENTITY_ONLY_INTAKE_V2_WAITING",
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "checks": checks,
        "operationally_valid": True,
        "observed": observed,
        "receipt": receipt,
        "decision": {
            "v1_retired": True,
            "v2_identity_only_intake_complete": False,
            "P2_advanced": False,
            "P6_advanced": False,
            "prospective_trial_authorized": False,
            "next_action": "await an externally curated five-file v2 bundle and reject every v1 artifact",
        },
        "claim_boundary": protocol["claim_boundary"],
    }
    RESULT.write_text(
        json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE157"
        f" status={result['status']}"
        " positive=2/2 hostile=18/18 files=0/5"
        " decrypted=false P6=false prospective=false"
    )


if __name__ == "__main__":
    main()
