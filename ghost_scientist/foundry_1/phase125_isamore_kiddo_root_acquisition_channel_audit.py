#!/usr/bin/env python3
"""Freeze the exact kiddo-root acquisition boundary without fabricating source."""

from __future__ import annotations

import hashlib
import json
import pathlib
import shutil
import subprocess
import tomllib


HERE = pathlib.Path(__file__).resolve().parent
SOURCE = HERE / "external_controls/isamore/source"
VENDOR = HERE / "external_controls/isamore/vendor"
EVIDENCE = (
    HERE
    / "external_controls/isamore/upstream_evidence"
    / "kiddo-20560517"
    / "Cargo.toml"
)
PRIOR = HERE / "results/phase124_isamore_kiddo_partial_family_bridge_audit.json"
RESULT = HERE / "results/phase125_isamore_kiddo_root_acquisition_channel_audit.json"
LOCKED_CHECKSUM = (
    "07ab03cc75e18eb1eec59f4037e2e17ce9d13920f0013b0719dea613d9414e4e"
)
REPOSITORY = "sdd-org/kiddo"
RELEASE_ADJACENT_COMMIT = "20560517c7e06d71a6887a7662b89b70091ef8db"
MANIFEST_BLOB = "1f5e83b6e242fb98db8ab33fd256e889e7854af7"
REGISTRY_URL = (
    "https://static.crates.io/crates/kiddo/kiddo-5.2.4.crate"
)
DIAGNOSTIC_CDN_IP = "140.248.138.137"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_blob(path: pathlib.Path) -> str:
    raw = path.read_bytes()
    return hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()


def locked_kiddo() -> dict:
    packages = tomllib.loads(
        (SOURCE / "Cargo.lock").read_text(encoding="utf-8")
    )["package"]
    matches = [
        row
        for row in packages
        if row["name"] == "kiddo" and row["version"] == "5.2.4"
    ]
    if len(matches) != 1 or matches[0].get("checksum") != LOCKED_CHECKSUM:
        raise RuntimeError("locked kiddo identity changed")
    return matches[0]


def local_archives() -> list[pathlib.Path]:
    cache = pathlib.Path.home() / ".cargo/registry/cache"
    return sorted(cache.rglob("kiddo-5.2.4.crate"))


def probe(args: list[str]) -> dict:
    completed = subprocess.run(
        args,
        cwd=HERE,
        text=True,
        capture_output=True,
        timeout=20,
        check=False,
    )
    return {
        "argv": args,
        "returncode": completed.returncode,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
    }


def validate_local_boundary() -> dict:
    locked = locked_kiddo()
    manifest = tomllib.loads(EVIDENCE.read_text(encoding="utf-8"))
    if (
        git_blob(EVIDENCE) != MANIFEST_BLOB
        or manifest["package"]["name"] != "kiddo"
        or manifest["package"]["version"] != "5.2.1"
        or manifest["dependencies"]["cmov"] != "0.4"
    ):
        raise RuntimeError("release-adjacent kiddo manifest changed")
    archives = local_archives()
    if archives:
        raise RuntimeError(
            "kiddo 5.2.4 archive became available; advance instead of "
            "replaying the acquisition-boundary phase"
        )
    if (VENDOR / "kiddo-5.2.4").exists():
        raise RuntimeError(
            "kiddo 5.2.4 source became available; advance instead of "
            "replaying the acquisition-boundary phase"
        )
    return locked


def create() -> dict:
    prior = json.loads(PRIOR.read_text())
    if not (
        prior["status"]
        == "ISAMORE_KIDDO_PARTIAL_FAMILY_AUTHENTICATED_NO_STOP_ADVANCE"
        and prior["next_build_stop"]["package"] == "kiddo"
        and prior["checks"]["kiddo_root_source_acquired"] is False
    ):
        raise RuntimeError("prior kiddo boundary changed")
    locked = validate_local_boundary()
    curl = shutil.which("curl")
    if curl is None:
        raise RuntimeError("curl unavailable for bounded transport probes")
    dns_probe = probe(
        [
            curl,
            "--fail",
            "--location",
            "--max-time",
            "8",
            "--user-agent",
            "cargo/1.0",
            "--output",
            "/dev/null",
            REGISTRY_URL,
        ]
    )
    direct_probe = probe(
        [
            curl,
            "--resolve",
            f"static.crates.io:443:{DIAGNOSTIC_CDN_IP}",
            "--fail",
            "--location",
            "--max-time",
            "8",
            "--user-agent",
            "cargo/1.0",
            "--output",
            "/dev/null",
            REGISTRY_URL,
        ]
    )
    if (
        dns_probe["returncode"] == 0
        or direct_probe["returncode"] == 0
        or "Could not resolve host" not in dns_probe["stderr"]
        or "Failed to connect" not in direct_probe["stderr"]
    ):
        raise RuntimeError("registry transport result changed")
    return {
        "version": "FOUNDRY_ISAMORE_KIDDO_ROOT_ACQUISITION_CHANNEL_AUDIT_V1",
        "status": "ISAMORE_KIDDO_ROOT_AVAILABLE_CHANNELS_AUDITED_NO_SOURCE",
        "locked_root": {
            "package": locked["name"],
            "version": locked["version"],
            "sha256": locked["checksum"],
        },
        "official_repository_evidence": {
            "repository": REPOSITORY,
            "revision": RELEASE_ADJACENT_COMMIT,
            "manifest_path": str(EVIDENCE.relative_to(HERE)),
            "manifest_git_blob_sha1": MANIFEST_BLOB,
            "manifest_sha256": sha256(EVIDENCE),
            "manifest_declared_version": "5.2.1",
            "manifest_cmov_requirement": "0.4",
        },
        "registry_transport": {
            "canonical_static_url": REGISTRY_URL,
            "dns_probe": dns_probe,
            "direct_ip_diagnostic_probe": direct_probe,
            "diagnostic_cdn_ip_not_identity_evidence": True,
        },
        "checks": {
            "locked_registry_identity_authenticated": True,
            "release_adjacent_manifest_byte_authenticated": True,
            "release_adjacent_manifest_matches_locked_version": False,
            "local_exact_archive_present": False,
            "local_exact_source_present": False,
            "shell_registry_transport_available": False,
            "kiddo_root_source_acquired": False,
            "resolver_stop_advanced": False,
            "algorithm_compilation_reached": False,
            "algorithm_execution_reached": False,
        },
        "next_build_stop": {
            "class": "MISSING_OFFLINE_REGISTRY_PACKAGE",
            "package": "kiddo",
            "version": "5.2.4",
        },
        "control_executed": False,
        "source_faithful_controls_reproduced": 3,
        "controls_required": 4,
        "P1_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
        "claim_boundary": (
            "The lock authenticates kiddo 5.2.4 and its registry checksum. "
            "The byte-pinned release-adjacent official manifest authenticates "
            "commit 20560517 but declares 5.2.1. No exact local archive or "
            "source exists, and both bounded shell registry probes failed. "
            "The repository manifest was not rewritten and no source identity "
            "is inferred from the nearby commit."
        ),
        "next_action": (
            "continue exact direct-dependency source closure while preserving "
            "the kiddo root as an unresolved acquisition boundary"
        ),
    }


def verify(payload: dict) -> None:
    validate_local_boundary()
    dns_probe = payload["registry_transport"]["dns_probe"]
    direct_probe = payload["registry_transport"]["direct_ip_diagnostic_probe"]
    if not (
        payload["status"]
        == "ISAMORE_KIDDO_ROOT_AVAILABLE_CHANNELS_AUDITED_NO_SOURCE"
        and payload["locked_root"]["sha256"] == LOCKED_CHECKSUM
        and payload["official_repository_evidence"]["manifest_git_blob_sha1"]
        == MANIFEST_BLOB
        and payload["official_repository_evidence"][
            "manifest_declared_version"
        ]
        == "5.2.1"
        and dns_probe["returncode"] != 0
        and "Could not resolve host" in dns_probe["stderr"]
        and direct_probe["returncode"] != 0
        and "Failed to connect" in direct_probe["stderr"]
        and payload["checks"]["kiddo_root_source_acquired"] is False
        and payload["checks"]["resolver_stop_advanced"] is False
        and payload["control_executed"] is False
        and payload["validation_v6_accessed"] is False
    ):
        raise RuntimeError("frozen kiddo acquisition boundary changed")


def main() -> None:
    if RESULT.exists():
        payload = json.loads(RESULT.read_text())
        verify(payload)
        mode = "VERIFY_FROZEN"
    else:
        payload = create()
        verify(payload)
        RESULT.write_text(canonical(payload) + "\n")
        mode = "CREATE"
    print(
        "FOUNDRY_PHASE125_ISAMORE_KIDDO_ROOT_ACQUISITION"
        " status=AVAILABLE_CHANNELS_AUDITED_NO_SOURCE"
        " lock=5.2.4 repo_manifest=5.2.1 archive=false"
        " transport=false stop=kiddo compiled=false executed=false"
        f" evidence={mode}"
    )


if __name__ == "__main__":
    main()
