#!/usr/bin/env python3
"""Falsify and execute the frozen validation-v7 identity-only intake."""

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
from typing import Any

from independent_validation_v7_identity_only_intake import (
    IndependentV7Reject,
    inspect as independent_inspect,
    verify_complete as independent_verify_complete,
)
from resource_meter_v2 import run_metered_tree
from validation_v7_identity_only_intake import (
    V7IntakeReject,
    canonical,
    inspect_inbox,
    validate_complete,
)


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/VALIDATION_V7_IDENTITY_ONLY_INTAKE_PROTOCOL_V1.json"
)
FREEZE = HERE / "results/validation_v7_identity_only_intake_v1_freeze.json"
INBOX = HERE / "validation_v7_sealed_inbox"
WORKER_RESULT = (
    HERE / "results/phase155_validation_v7_identity_only_intake_worker.json"
)
RESULT = HERE / "results/phase155_validation_v7_identity_only_intake.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(arguments: list[str]) -> bytes:
    process = subprocess.run(
        arguments,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if process.returncode:
        raise RuntimeError(
            f"command failed: {' '.join(arguments)}: "
            + process.stderr.decode(errors="replace")
        )
    return process.stdout


def deterministic_ciphertext(size: int = 8192) -> bytes:
    output = bytearray()
    index = 0
    while len(output) < size:
        output.extend(
            hashlib.sha256(f"v7-fixture-block:{index}".encode()).digest()
        )
        index += 1
    return bytes(output[:size])


def fingerprint(public_key: pathlib.Path) -> str:
    der = run(
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
    return hashlib.sha256(der).hexdigest()


def commitment(field: str, index: int) -> str:
    return hashlib.sha256(f"v7:{field}:{index}".encode()).hexdigest()


def sign(directory: pathlib.Path, private_key: pathlib.Path) -> None:
    manifest_path = directory / "public_manifest.v1.json"
    value = json.loads(manifest_path.read_text())
    manifest_path.write_bytes(canonical(value))
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
            str(directory / "public_manifest.v1.sig"),
            str(manifest_path),
        ]
    )


def build_fixture(root: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path]:
    directory = root / "valid"
    directory.mkdir()
    private_key = root / "fixture_private_key.pem"
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
    payload_digest = hashlib.sha256(payload).hexdigest()
    (directory / "payload.v7.enc").write_bytes(payload)
    (directory / "payload.v7.sha256").write_text(
        f"{payload_digest}  payload.v7.enc\n"
    )
    source_fields = (
        "repository_commitment_sha256",
        "revision_commitment_sha256",
        "family_commitment_sha256",
        "semantic_domain_commitment_sha256",
        "license_commitment_sha256",
        "source_tree_sha256",
    )
    sources = []
    for index in range(4):
        row = {"opaque_source_id": f"src_{index + 1:024x}"}
        row.update(
            {
                field: commitment(field, index)
                for field in source_fields
            }
        )
        sources.append(row)
    protocol = json.loads(PROTOCOL.read_text())
    manifest = {
        "version": "FOUNDRY_VALIDATION_V7_PUBLIC_MANIFEST_V1",
        "corpus_id": "v7-" + "1" * 32,
        "created_utc": "2026-07-30T23:00:00Z",
        "curator_key_fingerprint_sha256": fingerprint(public_key),
        "selection_attestation": protocol["public_manifest_contract"][
            "selection_attestation_exact"
        ],
        "sources": sources,
        "payload": {
            "ciphertext_sha256": payload_digest,
            "ciphertext_bytes": len(payload),
            "encryption": "AES-256-GCM",
            "nonce_base64": base64.b64encode(bytes(range(12))).decode(),
            "authentication_tag_base64": base64.b64encode(
                bytes(range(16))
            ).decode(),
            "plaintext_tree_sha256": hashlib.sha256(
                b"unavailable-fixture-plaintext-tree"
            ).hexdigest(),
        },
    }
    (directory / "public_manifest.v1.json").write_bytes(canonical(manifest))
    sign(directory, private_key)
    return directory, private_key


def worker() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    with tempfile.TemporaryDirectory(prefix="foundry-v7-intake-") as name:
        root = pathlib.Path(name)
        valid, private_key = build_fixture(root)
        primary_valid = validate_complete(valid, protocol)
        independent_valid = independent_verify_complete(valid, protocol)
        comparable_fields = (
            "status",
            "corpus_id",
            "sources",
            "distinct_repository_commitments",
            "distinct_semantic_domain_commitments",
            "manifest_sha256",
            "payload_sha256",
            "payload_bytes",
            "curator_key_fingerprint_sha256",
            "curator_key_bits",
            "manifest_signature_verified",
            "payload_decrypted",
        )
        if any(
            primary_valid[field] != independent_valid[field]
            for field in comparable_fields
        ) or abs(
            primary_valid["payload_entropy_bits_per_byte"]
            - independent_valid["payload_entropy_bits_per_byte"]
        ) > 1.0e-12:
            raise RuntimeError("v7 valid-fixture validators disagree")

        hostile = []

        def case(case_name: str, mutate, *, resign: bool = False) -> None:
            target = root / f"case-{len(hostile):02d}"
            shutil.copytree(valid, target)
            mutate(target)
            if resign:
                sign(target, private_key)
            primary = independent = False
            try:
                validate_complete(target, protocol)
            except (
                V7IntakeReject,
                KeyError,
                TypeError,
                ValueError,
                json.JSONDecodeError,
            ):
                primary = True
            try:
                independent_verify_complete(target, protocol)
            except (
                IndependentV7Reject,
                KeyError,
                TypeError,
                ValueError,
                json.JSONDecodeError,
            ):
                independent = True
            hostile.append(
                {
                    "case": case_name,
                    "primary_rejected": primary,
                    "independent_rejected": independent,
                }
            )

        case(
            "missing_required_file",
            lambda path: (path / "payload.v7.sha256").unlink(),
        )
        case(
            "unknown_file",
            lambda path: (path / "surprise.bin").write_bytes(b"x"),
        )
        case(
            "private_key_present",
            lambda path: shutil.copyfile(
                private_key, path / "curator_public_key.pem"
            ),
        )
        case(
            "plaintext_source_like_file",
            lambda path: (path / "runtime.py").write_text("pass\n"),
        )

        def manifest_mutation(path: pathlib.Path, mutate) -> None:
            manifest_path = path / "public_manifest.v1.json"
            value = json.loads(manifest_path.read_text())
            mutate(value)
            manifest_path.write_bytes(canonical(value))

        case(
            "unknown_manifest_field",
            lambda path: manifest_mutation(
                path, lambda value: value.update(unknown=True)
            ),
            resign=True,
        )
        case(
            "plaintext_repository_identity_field",
            lambda path: manifest_mutation(
                path,
                lambda value: value["sources"][0].update(
                    repository="forbidden/repository"
                ),
            ),
            resign=True,
        )
        case(
            "duplicate_opaque_source_id",
            lambda path: manifest_mutation(
                path,
                lambda value: value["sources"][1].update(
                    opaque_source_id=value["sources"][0][
                        "opaque_source_id"
                    ]
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
            "selection_attestation_weakened",
            lambda path: manifest_mutation(
                path,
                lambda value: value["selection_attestation"].update(
                    independently_selected_without_candidate_matching=False
                ),
            ),
            resign=True,
        )
        case(
            "ciphertext_digest_mismatch",
            lambda path: manifest_mutation(
                path,
                lambda value: value["payload"].update(
                    ciphertext_sha256="0" * 64
                ),
            ),
            resign=True,
        )
        case(
            "digest_sidecar_mismatch",
            lambda path: (path / "payload.v7.sha256").write_text(
                "0" * 64 + "  payload.v7.enc\n"
            ),
        )

        def replace_payload(path: pathlib.Path, payload: bytes) -> None:
            digest = hashlib.sha256(payload).hexdigest()
            (path / "payload.v7.enc").write_bytes(payload)
            (path / "payload.v7.sha256").write_text(
                f"{digest}  payload.v7.enc\n"
            )
            manifest_mutation(
                path,
                lambda value: value["payload"].update(
                    ciphertext_sha256=digest,
                    ciphertext_bytes=len(payload),
                ),
            )

        case(
            "ciphertext_too_small",
            lambda path: replace_payload(path, deterministic_ciphertext(32)),
            resign=True,
        )
        case(
            "ciphertext_entropy_too_low",
            lambda path: replace_payload(path, b"\0" * 8192),
            resign=True,
        )
        case(
            "public_key_fingerprint_mismatch",
            lambda path: manifest_mutation(
                path,
                lambda value: value.update(
                    curator_key_fingerprint_sha256="0" * 64
                ),
            ),
            resign=True,
        )
        case(
            "manifest_signature_mismatch",
            lambda path: (path / "public_manifest.v1.sig").write_bytes(
                b"\0"
                + (path / "public_manifest.v1.sig").read_bytes()[1:]
            ),
        )
        real_primary = inspect_inbox(INBOX, protocol)
        real_independent = independent_inspect(INBOX, protocol)
        if real_primary != real_independent:
            raise RuntimeError("v7 real-inbox validators disagree")
        payload = {
            "version": "FOUNDRY_VALIDATION_V7_IDENTITY_ONLY_WORKER_V1",
            "synthetic_positive": primary_valid,
            "hostile_rejections": hostile,
            "real_inbox": real_primary,
            "summary": {
                "positive_validators": 2,
                "hostile_cases": len(hostile),
                "hostile_rejected_twice": sum(
                    row["primary_rejected"]
                    and row["independent_rejected"]
                    for row in hostile
                ),
                "real_present_required_files": len(
                    real_primary.get("present_required_files", [])
                ),
                "real_missing_required_files": len(
                    real_primary.get("missing_required_files", [])
                ),
            },
            "payload_decrypted": False,
            "source_runtime_graph_shape_or_outcome_accessed": False,
            "prospective_trial_authorized": False,
        }
        WORKER_RESULT.write_text(
            json.dumps(payload, sort_keys=True, separators=(",", ":"))
            + "\n"
        )
        print(
            "FOUNDRY_PHASE155_WORKER"
            f" positive=2/2"
            f" hostile={payload['summary']['hostile_rejected_twice']}/16"
            f" real_status={real_primary['status']}"
            f" real_present={payload['summary']['real_present_required_files']}/5"
        )


def main() -> None:
    if "--worker" in sys.argv:
        worker()
        return
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    providers_exact = all(
        sha(HERE / row["path"]) == row["sha256"]
        for row in protocol["provider_records"]
    )
    freeze_exact = (
        freeze["protocol_sha256"] == sha(PROTOCOL)
        and freeze["provider_records"] == protocol["provider_records"]
        and freeze["required_files"] == protocol["required_files"]
        and freeze["candidate_visible_boundary"]
        == protocol["candidate_visible_boundary"]
        and freeze["public_manifest_contract"]
        == protocol["public_manifest_contract"]
        and freeze["cryptographic_policy"]
        == protocol["cryptographic_policy"]
        and freeze["decision_rule"] == protocol["decision_rule"]
        and freeze["validation_v7_accessed"] is False
    )
    limits = {
        "wall_limit_seconds": protocol["resource_limits"]["wall_seconds"],
        "cpu_limit_seconds": protocol["resource_limits"]["cpu_seconds"],
        "rss_limit_kib": protocol["resource_limits"]["rss_kib"],
    }
    receipt = run_metered_tree(
        [
            str(pathlib.Path(sys.executable).resolve()),
            str(__file__),
            "--worker",
        ],
        cwd=HERE,
        environment={"PYTHONHASHSEED": "0"},
        **limits,
    )
    natural = (
        receipt["returncode"] == 0
        and receipt["termination"] == "natural"
        and receipt["process_group_reaped"] is True
        and "FOUNDRY_PHASE155_WORKER" in receipt["stdout_text"]
    )
    observed = (
        json.loads(WORKER_RESULT.read_text())
        if natural and WORKER_RESULT.exists()
        else {}
    )
    summary = observed.get("summary", {})
    real = observed.get("real_inbox", {})
    checks = {
        "protocol_freeze_and_providers_exact": providers_exact and freeze_exact,
        "metered_worker_terminated_naturally": natural,
        "complete_process_tree_accounting": (
            natural
            and receipt["observed_process_count"] >= 1
            and receipt["peak_group_rss_kib"] > 0
            and receipt["rusage_user_cpu_ns"]
            + receipt["rusage_system_cpu_ns"]
            > 0
        ),
        "synthetic_positive_accepted_twice": (
            summary.get("positive_validators") == 2
            and observed.get("synthetic_positive", {}).get("payload_decrypted")
            is False
        ),
        "sixteen_hostile_cases_rejected_twice": (
            summary.get("hostile_cases") == 16
            and summary.get("hostile_rejected_twice") == 16
        ),
        "real_inbox_state_is_valid_decision": real.get("status")
        in {
            "VALIDATION_V7_IDENTITY_ONLY_INTAKE_WAITING",
            "VALIDATION_V7_IDENTITY_ONLY_INTAKE_COMPLETE",
        },
        "no_payload_decryption": observed.get("payload_decrypted") is False,
        "no_source_runtime_graph_shape_or_outcome_access": observed.get(
            "source_runtime_graph_shape_or_outcome_accessed"
        )
        is False,
        "prospective_unauthorized": observed.get(
            "prospective_trial_authorized"
        )
        is False,
    }
    valid = all(checks.values())
    complete = (
        valid
        and real.get("status")
        == "VALIDATION_V7_IDENTITY_ONLY_INTAKE_COMPLETE"
    )
    waiting = (
        valid
        and real.get("status")
        == "VALIDATION_V7_IDENTITY_ONLY_INTAKE_WAITING"
    )
    status = (
        "VALIDATION_V7_IDENTITY_ONLY_INTAKE_COMPLETE"
        if complete
        else (
            "VALIDATION_V7_IDENTITY_ONLY_INTAKE_WAITING"
            if waiting
            else "VALIDATION_V7_IDENTITY_ONLY_INTAKE_INVALID"
        )
    )
    payload = {
        "version": "FOUNDRY_VALIDATION_V7_IDENTITY_ONLY_INTAKE_RESULT_V1",
        "status": status,
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "runner_records": [
            {"path": pathlib.Path(__file__).name, "sha256": sha(pathlib.Path(__file__))},
            {
                "path": "validation_v7_identity_only_intake.py",
                "sha256": sha(HERE / "validation_v7_identity_only_intake.py"),
            },
            {
                "path": "independent_validation_v7_identity_only_intake.py",
                "sha256": sha(
                    HERE
                    / "independent_validation_v7_identity_only_intake.py"
                ),
            },
        ],
        "limits": limits,
        "receipt": receipt,
        "checks": checks,
        "operationally_valid": valid,
        "observed": observed,
        "decision": {
            "identity_only_intake_complete": complete,
            "P2_advanced": False,
            "P6_advanced": False,
            "next_action": (
                protocol["decision_rule"]["complete_next_action"]
                if complete
                else (
                    protocol["decision_rule"]["waiting_next_action"]
                    if waiting
                    else protocol["decision_rule"]["invalid_next_action"]
                )
            ),
            "prospective_trial_authorized": False,
        },
        "claim_boundary": protocol["claim_boundary"],
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE155_VALIDATION_V7_INTAKE"
        f" status={status}"
        f" positive={summary.get('positive_validators', 0)}/2"
        f" hostile={summary.get('hostile_rejected_twice', 0)}/16"
        f" real_present={summary.get('real_present_required_files', 0)}/5"
        " decrypted=false P6=false prospective=false"
    )
    if not valid:
        raise RuntimeError(
            "validation-v7 intake invalid: "
            + json.dumps(
                {
                    "failed": [
                        key for key, value in checks.items() if not value
                    ],
                    "stderr": receipt["stderr_text"],
                },
                sort_keys=True,
                separators=(",", ":"),
            )
        )


if __name__ == "__main__":
    main()
