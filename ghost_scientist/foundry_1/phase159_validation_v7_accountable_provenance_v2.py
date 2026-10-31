#!/usr/bin/env python3
"""Falsify and execute accountable validation-v7 provenance v2."""

from __future__ import annotations

import copy
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

from independent_validation_v7_accountable_provenance_v2 import (
    IndependentProvenanceV2Reject,
    inspect as independent_inspect,
    verify_complete as independent_verify,
)
from phase157_validation_v7_identity_only_intake_v2 import build_fixture
from resource_meter_v2 import run_metered_tree
from validation_v7_accountable_provenance_v2 import (
    V7ProvenanceV2Reject,
    canonical,
    inspect_state,
    key_fingerprint,
    roster_root,
    source_choice_root,
    validate_complete,
)


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/VALIDATION_V7_ACCOUNTABLE_PROVENANCE_PROTOCOL_V2.json"
)
INTAKE_PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/VALIDATION_V7_IDENTITY_ONLY_INTAKE_PROTOCOL_V2.json"
)
FREEZE = HERE / "results/validation_v7_accountable_provenance_v2_freeze.json"
REAL_TRUST = HERE / "validation_v7_external_trust_root"
REAL_PROVENANCE = HERE / "validation_v7_provenance_inbox"
REAL_BUNDLE = HERE / "validation_v7_sealed_inbox"
WORKER_RESULT = HERE / "results/phase159_validation_v7_accountable_provenance_v2_worker.json"
RESULT = HERE / "results/phase159_validation_v7_accountable_provenance_v2.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def h(label: str) -> str:
    return hashlib.sha256(label.encode()).hexdigest()


def run(args: list[str]) -> bytes:
    process = subprocess.run(
        args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False
    )
    if process.returncode:
        raise RuntimeError(process.stderr.decode(errors="replace"))
    return process.stdout


def generate_key(
    root: pathlib.Path, label: str, public_destination: pathlib.Path
) -> pathlib.Path:
    private = root / f"{label}-private.pem"
    run(
        [
            "openssl",
            "genpkey",
            "-algorithm",
            "RSA",
            "-pkeyopt",
            "rsa_keygen_bits:3072",
            "-out",
            str(private),
        ]
    )
    run(
        [
            "openssl",
            "pkey",
            "-in",
            str(private),
            "-pubout",
            "-out",
            str(public_destination),
        ]
    )
    return private


def sign(private: pathlib.Path, message: pathlib.Path, signature: pathlib.Path) -> None:
    value = json.loads(message.read_text())
    message.write_bytes(canonical(value))
    run(
        [
            "openssl",
            "dgst",
            "-sha256",
            "-sign",
            str(private),
            "-sigopt",
            "rsa_padding_mode:pss",
            "-sigopt",
            "rsa_pss_saltlen:digest",
            "-out",
            str(signature),
            str(message),
        ]
    )


def build_provenance_fixture(
    root: pathlib.Path, protocol: dict, intake_protocol: dict
) -> tuple[pathlib.Path, pathlib.Path, pathlib.Path, dict[str, pathlib.Path]]:
    bundle, curator_private = build_fixture(root, intake_protocol)
    trust = root / "trust"
    provenance = root / "provenance"
    trust.mkdir()
    provenance.mkdir()
    shutil.copyfile(
        bundle / "curator_public_key.pem",
        provenance / "curator_public_key.pem",
    )
    sponsor_private = generate_key(
        root, "sponsor", provenance / "sponsor_public_key.pem"
    )
    reviewer_private = generate_key(
        root, "reviewer", provenance / "reviewer_public_key.pem"
    )
    log_private = generate_key(
        root, "external-log", provenance / "external_log_public_key.pem"
    )
    sponsor_fp = key_fingerprint(provenance / "sponsor_public_key.pem")[0]
    curator_fp = key_fingerprint(provenance / "curator_public_key.pem")[0]
    reviewer_fp = key_fingerprint(provenance / "reviewer_public_key.pem")[0]
    log_fp = key_fingerprint(provenance / "external_log_public_key.pem")[0]
    (trust / "authorized_sponsor_fingerprint.sha256").write_text(
        sponsor_fp + "\n"
    )
    roster = [h("candidate-team-member:1"), h("candidate-team-member:2")]
    roster_digest = roster_root(roster, protocol)
    rc = protocol["trust_registry_contract"]
    registry = {
        "version": rc["version"],
        "scope": rc["scope"],
        "enrolled_utc": "2026-07-30T22:00:00Z",
        "registration_method": rc["registration_method"],
        "sponsor_key_fingerprint_sha256": sponsor_fp,
        "candidate_team_identity_commitments": roster,
        "candidate_team_roster_root_sha256": roster_digest,
        "curator": {
            "opaque_actor_id": "actor_" + "1" * 24,
            "legal_identity_commitment_sha256": h("curator-identity"),
            "organization_commitment_sha256": h("curator-organization"),
            "public_key_fingerprint_sha256": curator_fp,
            "sponsor_review_receipt_sha256": h("curator-sponsor-review"),
            "key_purpose": rc["curator_key_purpose"],
            "conflict_check_completed": True,
        },
        "reviewer": {
            "opaque_actor_id": "actor_" + "2" * 24,
            "legal_identity_commitment_sha256": h("reviewer-identity"),
            "organization_commitment_sha256": h("reviewer-organization"),
            "public_key_fingerprint_sha256": reviewer_fp,
            "sponsor_review_receipt_sha256": h("reviewer-sponsor-review"),
            "key_purpose": rc["reviewer_key_purpose"],
            "conflict_check_completed": True,
        },
        "external_log": {
            "opaque_log_id": "log_" + "3" * 24,
            "organization_commitment_sha256": h("external-log-organization"),
            "public_key_fingerprint_sha256": log_fp,
            "sponsor_review_receipt_sha256": h("external-log-sponsor-review"),
            "key_purpose": rc["external_log_key_purpose"],
        },
    }
    registry_path = provenance / "trust_registry.v2.json"
    registry_path.write_bytes(canonical(registry))
    sign(
        sponsor_private,
        registry_path,
        provenance / "trust_registry.v2.sig",
    )
    bc = protocol["candidate_boundary_contract"]
    boundary = {
        "version": bc["version"],
        "snapshot_created_utc": "2026-07-30T22:05:00Z",
        **protocol["candidate_snapshot_contract"],
        "candidate_team_roster_root_sha256": roster_digest,
        "matcher_release_policy_sha256": h("matcher-release-policy-v2"),
        "matcher_released": False,
    }
    boundary_path = provenance / "candidate_boundary.v2.json"
    boundary_path.write_bytes(canonical(boundary))
    sign(
        sponsor_private,
        boundary_path,
        provenance / "candidate_boundary.v2.sig",
    )
    manifest_path = bundle / "public_manifest.v2.json"
    manifest = json.loads(manifest_path.read_text())
    choice_root = source_choice_root(manifest["sources"], protocol)
    sc = protocol["provenance_statement_contract"]
    statement = {
        "version": sc["version"],
        "attestation_id": "att_" + "4" * 32,
        "issued_utc": "2026-07-30T22:15:00Z",
        "corpus_id": manifest["corpus_id"],
        "public_manifest_sha256": sha(manifest_path),
        "payload_ciphertext_sha256": sha(bundle / "payload.v7.enc"),
        "source_choice_set_root_sha256": choice_root,
        "source_count": 4,
        "trust_registry_sha256": sha(registry_path),
        "candidate_boundary_sha256": sha(boundary_path),
        "selection_log_commitment_sha256": h("sealed-selection-log"),
        "choices_finalized_utc": "2026-07-30T22:10:00Z",
        "statements": sc["statements_exact"],
        "claim_boundary": sc["claim_boundary_exact"],
    }
    statement_path = provenance / "provenance_statement.v2.json"
    statement_path.write_bytes(canonical(statement))
    sign(
        curator_private,
        statement_path,
        provenance / "curator_statement.sig",
    )
    sign(
        reviewer_private,
        statement_path,
        provenance / "reviewer_statement.sig",
    )
    lc = protocol["external_log_contract"]
    log_entry = {
        "version": lc["version"],
        "opaque_log_id": registry["external_log"]["opaque_log_id"],
        "sequence_number": 7,
        "integrated_utc": "2026-07-30T22:20:00Z",
        "previous_checkpoint_sha256": h("previous-external-checkpoint"),
        "provenance_statement_sha256": sha(statement_path),
        "selection_log_commitment_sha256": statement[
            "selection_log_commitment_sha256"
        ],
        "source_choice_set_root_sha256": choice_root,
    }
    log_path = provenance / "external_log_entry.v2.json"
    log_path.write_bytes(canonical(log_entry))
    sign(
        log_private,
        log_path,
        provenance / "external_log_entry.v2.sig",
    )
    return (
        trust,
        provenance,
        bundle,
        {
            "sponsor": sponsor_private,
            "curator": curator_private,
            "reviewer": reviewer_private,
            "log": log_private,
        },
    )


def worker() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    intake_protocol = json.loads(INTAKE_PROTOCOL.read_text())
    with tempfile.TemporaryDirectory(prefix="foundry-v7-provenance-v2-") as name:
        root = pathlib.Path(name)
        trust, provenance, bundle, private = build_provenance_fixture(
            root, protocol, intake_protocol
        )
        primary = validate_complete(
            trust, provenance, bundle, protocol, intake_protocol
        )
        independent = independent_verify(
            trust, provenance, bundle, protocol, intake_protocol
        )
        if primary != independent:
            raise RuntimeError("positive provenance validators disagree")
        hostile = []

        def mutate_json(path: pathlib.Path, mutation) -> None:
            value = json.loads(path.read_text())
            mutation(value)
            path.write_bytes(canonical(value))

        def resign_all(
            target: pathlib.Path,
            *,
            registry: bool = False,
            boundary: bool = False,
            statement: bool = False,
            log: bool = False,
        ) -> None:
            if registry:
                sign(
                    private["sponsor"],
                    target / "provenance/trust_registry.v2.json",
                    target / "provenance/trust_registry.v2.sig",
                )
            if boundary:
                sign(
                    private["sponsor"],
                    target / "provenance/candidate_boundary.v2.json",
                    target / "provenance/candidate_boundary.v2.sig",
                )
            if statement:
                statement_path = target / "provenance/provenance_statement.v2.json"
                sign(
                    private["curator"],
                    statement_path,
                    target / "provenance/curator_statement.sig",
                )
                sign(
                    private["reviewer"],
                    statement_path,
                    target / "provenance/reviewer_statement.sig",
                )
            if log:
                sign(
                    private["log"],
                    target / "provenance/external_log_entry.v2.json",
                    target / "provenance/external_log_entry.v2.sig",
                )

        def case(name: str, mutation, **resign) -> None:
            target = root / f"hostile-{len(hostile):02d}"
            target.mkdir()
            shutil.copytree(trust, target / "trust")
            shutil.copytree(provenance, target / "provenance")
            shutil.copytree(bundle, target / "bundle")
            mutation(target)
            resign_all(target, **resign)
            primary_rejected = independent_rejected = False
            try:
                validate_complete(
                    target / "trust",
                    target / "provenance",
                    target / "bundle",
                    protocol,
                    intake_protocol,
                )
            except (
                V7ProvenanceV2Reject,
                KeyError,
                TypeError,
                ValueError,
                json.JSONDecodeError,
            ):
                primary_rejected = True
            try:
                independent_verify(
                    target / "trust",
                    target / "provenance",
                    target / "bundle",
                    protocol,
                    intake_protocol,
                )
            except (
                IndependentProvenanceV2Reject,
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

        p = lambda target, name: target / "provenance" / name
        case(
            "provenance_v1_artifact",
            lambda target: p(target, "trust_registry.v2.json").rename(
                p(target, "trust_registry.v1.json")
            ),
        )
        case(
            "untrusted_self_provided_sponsor_key",
            lambda target: (target / "trust/authorized_sponsor_fingerprint.sha256").write_text(
                "0" * 64 + "\n"
            ),
        )
        case(
            "missing_provenance_file",
            lambda target: p(target, "reviewer_statement.sig").unlink(),
        )
        case(
            "unknown_provenance_file",
            lambda target: p(target, "unknown.bin").write_bytes(b"x"),
        )
        case(
            "private_key_present",
            lambda target: shutil.copyfile(
                private["sponsor"], p(target, "sponsor_public_key.pem")
            ),
        )
        case(
            "noncanonical_json",
            lambda target: p(target, "trust_registry.v2.json").write_bytes(
                p(target, "trust_registry.v2.json").read_bytes() + b" "
            ),
        )
        case(
            "unknown_registry_field",
            lambda target: mutate_json(
                p(target, "trust_registry.v2.json"),
                lambda value: value.update(extra=True),
            ),
            registry=True,
        )
        case(
            "candidate_roster_root_mismatch",
            lambda target: mutate_json(
                p(target, "trust_registry.v2.json"),
                lambda value: value.update(
                    candidate_team_roster_root_sha256="0" * 64
                ),
            ),
            registry=True,
        )
        case(
            "curator_is_candidate_roster_member",
            lambda target: mutate_json(
                p(target, "trust_registry.v2.json"),
                lambda value: value["curator"].update(
                    legal_identity_commitment_sha256=value[
                        "candidate_team_identity_commitments"
                    ][0]
                ),
            ),
            registry=True,
        )
        case(
            "reviewer_is_candidate_roster_member",
            lambda target: mutate_json(
                p(target, "trust_registry.v2.json"),
                lambda value: value["reviewer"].update(
                    legal_identity_commitment_sha256=value[
                        "candidate_team_identity_commitments"
                    ][1]
                ),
            ),
            registry=True,
        )
        case(
            "duplicate_actor_identity",
            lambda target: mutate_json(
                p(target, "trust_registry.v2.json"),
                lambda value: value["reviewer"].update(
                    legal_identity_commitment_sha256=value["curator"][
                        "legal_identity_commitment_sha256"
                    ]
                ),
            ),
            registry=True,
        )
        case(
            "duplicate_actor_organization",
            lambda target: mutate_json(
                p(target, "trust_registry.v2.json"),
                lambda value: value["reviewer"].update(
                    organization_commitment_sha256=value["curator"][
                        "organization_commitment_sha256"
                    ]
                ),
            ),
            registry=True,
        )
        case(
            "duplicate_actor_public_key",
            lambda target: mutate_json(
                p(target, "trust_registry.v2.json"),
                lambda value: value["reviewer"].update(
                    public_key_fingerprint_sha256=value["curator"][
                        "public_key_fingerprint_sha256"
                    ]
                ),
            ),
            registry=True,
        )
        case(
            "duplicate_actor_sponsor_receipt",
            lambda target: mutate_json(
                p(target, "trust_registry.v2.json"),
                lambda value: value["reviewer"].update(
                    sponsor_review_receipt_sha256=value["curator"][
                        "sponsor_review_receipt_sha256"
                    ]
                ),
            ),
            registry=True,
        )
        case(
            "external_log_actor_organization_overlap",
            lambda target: mutate_json(
                p(target, "trust_registry.v2.json"),
                lambda value: value["external_log"].update(
                    organization_commitment_sha256=value["curator"][
                        "organization_commitment_sha256"
                    ]
                ),
            ),
            registry=True,
        )
        case(
            "conflict_check_false",
            lambda target: mutate_json(
                p(target, "trust_registry.v2.json"),
                lambda value: value["curator"].update(
                    conflict_check_completed=False
                ),
            ),
            registry=True,
        )
        case(
            "candidate_snapshot_binding_mismatch",
            lambda target: mutate_json(
                p(target, "candidate_boundary.v2.json"),
                lambda value: value.update(candidate_library_sha256="0" * 64),
            ),
            boundary=True,
        )
        case(
            "matcher_already_released",
            lambda target: mutate_json(
                p(target, "candidate_boundary.v2.json"),
                lambda value: value.update(matcher_released=True),
            ),
            boundary=True,
        )
        case(
            "unknown_statement_field",
            lambda target: mutate_json(
                p(target, "provenance_statement.v2.json"),
                lambda value: value.update(extra=True),
            ),
            statement=True,
        )
        case(
            "independence_statement_weakened",
            lambda target: mutate_json(
                p(target, "provenance_statement.v2.json"),
                lambda value: value["statements"].update(
                    source_selection_completed_before_candidate_fixed_or_control_matching=False
                ),
            ),
            statement=True,
        )
        case(
            "claim_inflation",
            lambda target: mutate_json(
                p(target, "provenance_statement.v2.json"),
                lambda value: value["claim_boundary"].update(P6_advanced=True),
            ),
            statement=True,
        )
        case(
            "wrong_v2_manifest_binding",
            lambda target: mutate_json(
                p(target, "provenance_statement.v2.json"),
                lambda value: value.update(public_manifest_sha256="0" * 64),
            ),
            statement=True,
        )
        case(
            "wrong_v2_payload_binding",
            lambda target: mutate_json(
                p(target, "provenance_statement.v2.json"),
                lambda value: value.update(payload_ciphertext_sha256="0" * 64),
            ),
            statement=True,
        )
        case(
            "wrong_source_choice_root",
            lambda target: mutate_json(
                p(target, "provenance_statement.v2.json"),
                lambda value: value.update(source_choice_set_root_sha256="0" * 64),
            ),
            statement=True,
        )
        case(
            "curator_signature_mismatch",
            lambda target: p(target, "curator_statement.sig").write_bytes(
                b"\0" + p(target, "curator_statement.sig").read_bytes()[1:]
            ),
        )
        case(
            "external_log_chronology_mismatch",
            lambda target: mutate_json(
                p(target, "external_log_entry.v2.json"),
                lambda value: value.update(integrated_utc="2026-07-30T22:01:00Z"),
            ),
            log=True,
        )
        real_primary = inspect_state(
            REAL_TRUST,
            REAL_PROVENANCE,
            REAL_BUNDLE,
            protocol,
            intake_protocol,
        )
        real_independent = independent_inspect(
            REAL_TRUST,
            REAL_PROVENANCE,
            REAL_BUNDLE,
            protocol,
            intake_protocol,
        )
        if real_primary != real_independent:
            raise RuntimeError("real provenance-state validators disagree")
        worker_result = {
            "version": "FOUNDRY_VALIDATION_V7_ACCOUNTABLE_PROVENANCE_V2_WORKER_V1",
            "synthetic_positive": primary,
            "hostile_rejections": hostile,
            "real_state": real_primary,
            "summary": {
                "positive_validators": 2,
                "hostile_cases": len(hostile),
                "hostile_rejected_twice": sum(
                    row["primary_rejected"] and row["independent_rejected"]
                    for row in hostile
                ),
                "real_trust_root_present": real_primary["trust_root_present"],
                "real_bundle_files_present": real_primary[
                    "bundle_files_present"
                ],
                "real_provenance_files_present": real_primary[
                    "provenance_files_present"
                ],
            },
            "payload_decrypted": False,
            "source_runtime_graph_shape_or_outcome_accessed": False,
        }
        WORKER_RESULT.write_text(
            json.dumps(worker_result, sort_keys=True, separators=(",", ":"))
            + "\n"
        )
        print(
            "FOUNDRY_PHASE159_WORKER positive=2/2"
            f" hostile={len(hostile)}/{len(hostile)}"
            f" real_status={real_primary['status']}"
        )


def main() -> None:
    if len(sys.argv) == 2 and sys.argv[1] == "--worker":
        worker()
        return
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    if not (
        freeze["status"]
        == "FROZEN_BEFORE_V2_VALIDATORS_EXTERNAL_TRUST_OR_PROVENANCE"
        and freeze["protocol_sha256"] == sha(PROTOCOL)
    ):
        raise RuntimeError("accountable provenance v2 freeze mismatch")
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
        "protocol_v2_frozen_before_validators_or_external_state": True,
        "synthetic_positive_accepted_twice": summary["positive_validators"] == 2,
        "twenty_six_hostile_cases_rejected_twice": (
            summary["hostile_cases"]
            == summary["hostile_rejected_twice"]
            == 26
        ),
        "four_signatures_verified_in_positive": (
            observed["synthetic_positive"]["signatures_verified"] == 4
        ),
        "roster_nonmembership_mechanically_checked": (
            observed["synthetic_positive"]["roster_nonmembership_checks"] == 2
        ),
        "source_choice_root_derived_from_four_v2_rows": (
            observed["synthetic_positive"]["source_count"] == 4
        ),
        "real_state_waits_for_external_sponsor_root": (
            observed["real_state"]["status"]
            == "WAITING_EXTERNAL_SPONSOR_TRUST_ROOT"
            and summary["real_trust_root_present"] is False
            and summary["real_bundle_files_present"] == 0
            and summary["real_provenance_files_present"] == 0
        ),
        "social_independence_not_claimed_as_cryptographic_proof": (
            observed["synthetic_positive"][
                "social_independence_cryptographically_proved"
            ]
            is False
        ),
        "no_payload_decryption_or_scientific_access": (
            observed["payload_decrypted"] is False
            and observed["source_runtime_graph_shape_or_outcome_accessed"]
            is False
        ),
        "metered_worker_passed": (
            receipt["returncode"] == 0
            and receipt["termination"] == "natural"
            and receipt["process_group_reaped"] is True
        ),
    }
    if not all(checks.values()):
        raise RuntimeError("accountable provenance v2 conformance failed")
    result = {
        "version": "FOUNDRY_VALIDATION_V7_ACCOUNTABLE_PROVENANCE_V2_RESULT_V1",
        "status": "WAITING_EXTERNAL_SPONSOR_TRUST_ROOT",
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "checks": checks,
        "operationally_valid": True,
        "observed": observed,
        "receipt": receipt,
        "decision": {
            "provenance_v1_retired": True,
            "accountable_provenance_v2_mechanism_conformant": True,
            "real_accountable_provenance_attested": False,
            "P2_advanced": False,
            "P6_advanced": False,
            "prospective_trial_authorized": False,
            "next_action": "obtain an out-of-band verified sponsor fingerprint, then the external v2 bundle and thirteen-file provenance package",
        },
        "claim_boundary": protocol["claim_boundary"],
    }
    RESULT.write_text(
        json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE159"
        f" status={result['status']}"
        " positive=2/2 hostile=26/26 signatures=4"
        " real_trust=false real_bundle=0/5 real_provenance=0/13"
        " decrypted=false P6=false prospective=false"
    )


if __name__ == "__main__":
    main()
