#!/usr/bin/env python3
"""Falsify the exact-artifact ingress gate and scan the real inbox."""

from __future__ import annotations

import hashlib
import io
import json
import pathlib
import tarfile
import tempfile

import isamore_exact_artifact_ingress as ingress


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/ISAMORE_EXACT_ARTIFACT_INGRESS_PROTOCOL_V1.json"
)
LOCK = HERE / "external_controls/isamore/source/Cargo.lock"
INBOX = HERE / "external_controls/isamore/artifact_inbox"
RESULT = (
    HERE
    / "results/phase136_isamore_exact_artifact_ingress_conformance.json"
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def archive_bytes(
    stem: str,
    *,
    member_name: str | None = None,
    kind: str = "regular",
    include_manifest: bool = True,
    duplicate: bool = False,
) -> bytes:
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:gz") as bundle:
        names = []
        if include_manifest:
            names.append(f"{stem}/Cargo.toml")
        names.append(member_name or f"{stem}/src/lib.rs")
        if duplicate:
            names.append(names[-1])
        for name in names:
            data = b"[package]\nname='probe'\nversion='0.0.0'\n"
            info = tarfile.TarInfo(name)
            if kind == "symlink" and name == names[-1]:
                info.type = tarfile.SYMTYPE
                info.linkname = "/etc/passwd"
                info.size = 0
            elif kind == "hardlink" and name == names[-1]:
                info.type = tarfile.LNKTYPE
                info.linkname = f"{stem}/Cargo.toml"
                info.size = 0
            else:
                info.size = len(data)
            bundle.addfile(
                info,
                None if info.issym() or info.islnk() else io.BytesIO(data),
            )
    return output.getvalue()


def expect_reject(
    name: str,
    raw: bytes,
    identity: ingress.Identity,
    *,
    archive_name: str | None = None,
    enforce_checksum: bool = False,
) -> dict[str, object]:
    with tempfile.TemporaryDirectory(prefix="foundry-ingress-hostile-") as tmp:
        path = pathlib.Path(tmp) / (archive_name or identity.filename)
        path.write_bytes(raw)
        try:
            ingress.validate_archive(
                path, identity, enforce_checksum=enforce_checksum
            )
        except ingress.IngressReject as exc:
            return {"name": name, "rejected": True, "reason": str(exc)}
    raise RuntimeError(f"hostile ingress case accepted: {name}")


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    for row in protocol["provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"ingress provider mismatch: {row['path']}")
    identities = ingress.locked_identities(LOCK)
    locked_count = len(identities)
    with tempfile.TemporaryDirectory(prefix="foundry-ingress-positive-") as tmp:
        root = pathlib.Path(tmp)
        stem = "probe-1.0.0"
        raw = archive_bytes(stem)
        path = root / f"{stem}.crate"
        path.write_bytes(raw)
        identity = ingress.Identity(
            "probe", "1.0.0", hashlib.sha256(raw).hexdigest()
        )
        members = ingress.validate_archive(path, identity)
        destination = root / "stage"
        published = ingress.stage_batch([(path, identity)], destination)
        positive = {
            "members": len(members),
            "published": [row.name for row in published],
            "manifest_present": (
                destination / stem / "Cargo.toml"
            ).is_file(),
        }
        preexisting_rejected = False
        try:
            ingress.stage_batch([(path, identity)], destination)
        except ingress.IngressReject:
            preexisting_rejected = True

    hostile = [
        expect_reject(
            "unknown_filename",
            archive_bytes(stem),
            identity,
            archive_name="unknown-9.9.9.crate",
        ),
        expect_reject(
            "checksum_mismatch",
            archive_bytes(stem) + b"checksum-mismatch",
            identity,
            enforce_checksum=True,
        ),
        expect_reject("malformed_gzip_tar", b"not a crate", identity),
        expect_reject(
            "absolute_member_path",
            archive_bytes(stem, member_name="/absolute"),
            identity,
        ),
        expect_reject(
            "parent_traversal_member",
            archive_bytes(stem, member_name=f"{stem}/../escape"),
            identity,
        ),
        expect_reject(
            "wrong_archive_root",
            archive_bytes(stem, member_name="other/src/lib.rs"),
            identity,
        ),
        expect_reject(
            "symbolic_link",
            archive_bytes(stem, kind="symlink"),
            identity,
        ),
        expect_reject(
            "hard_link",
            archive_bytes(stem, kind="hardlink"),
            identity,
        ),
        expect_reject(
            "duplicate_member",
            archive_bytes(stem, duplicate=True),
            identity,
        ),
        expect_reject(
            "missing_cargo_toml",
            archive_bytes(stem, include_manifest=False),
            identity,
        ),
    ]
    hostile.append(
        {
            "name": "preexisting_destination",
            "rejected": preexisting_rejected,
            "reason": "destination already exists",
        }
    )
    real_accepted, real_rejected = ingress.inspect_batch(INBOX, LOCK)
    checks = {
        "protocol_frozen_before_implementation": protocol[
            "frozen_before_ingress_implementation_or_execution"
        ]
        is True,
        "all_registry_lock_identities_loaded": locked_count >= 100,
        "synthetic_exact_archive_validated": (
            positive["members"] == 2
            and positive["published"] == [stem]
            and positive["manifest_present"] is True
        ),
        "eleven_hostile_cases_rejected": (
            len(hostile) == 11 and all(row["rejected"] for row in hostile)
        ),
        "atomic_stage_has_no_real_side_effect": len(real_accepted) == 0,
        "real_inbox_has_no_invalid_artifacts": len(real_rejected) == 0,
        "P1_not_advanced_by_gate": protocol["claim_boundary"][
            "ingress_conformance_may_advance_P1"
        ]
        is False,
        "validation_v6_unread": protocol["claim_boundary"][
            "validation_v6_accessed"
        ]
        is False,
    }
    if not all(checks.values()):
        raise RuntimeError("ISAMORE exact-artifact ingress conformance failed")
    payload = {
        "version":
        "FOUNDRY_ISAMORE_EXACT_ARTIFACT_INGRESS_CONFORMANCE_V1",
        "status": "ISAMORE_EXACT_ARTIFACT_INGRESS_CONFORMANCE_PASS",
        "protocol_sha256": sha(PROTOCOL),
        "implementation_sha256": sha(
            HERE / "isamore_exact_artifact_ingress.py"
        ),
        "checks": checks,
        "locked_registry_identities": locked_count,
        "synthetic_positive": positive,
        "hostile_rejections": hostile,
        "real_inbox": {
            "path": str(INBOX.relative_to(HERE)),
            "accepted": len(real_accepted),
            "rejected": len(real_rejected),
            "exact_artifacts_acquired": 0,
        },
        "P1_complete": False,
        "source_faithful_controls_reproduced": 3,
        "production_integrated_arms": 6,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
        "next_action": (
            "place transported name-version.crate bytes in the isolated inbox; "
            "the unchanged gate can authenticate and atomically stage them "
            "without version edits or substitute-source decisions"
        ),
        "claim_boundary": (
            "The gate proves fail-closed artifact admission and atomic staging. "
            "Its synthetic archive tests the verifier only. The real inbox is "
            "empty, so no upstream source was acquired and P1 did not advance."
        ),
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE136_ISAMORE_EXACT_ARTIFACT_INGRESS"
        f" status={payload['status']}"
        f" locked={locked_count} hostile={len(hostile)}"
        " real_exact=0 P1=false prospective=false"
    )


if __name__ == "__main__":
    main()
