#!/usr/bin/env python3
"""Advance the ISAMORE build through the locked Crossbeam closure."""

from __future__ import annotations

import hashlib
import json
import pathlib
import shutil
import tomllib

from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
SOURCE = HERE / "external_controls/isamore/source"
VENDOR = HERE / "external_controls/isamore/vendor/crossbeam-0.8.4"
PRIOR = HERE / "results/phase113_isamore_colored_bridge_audit.json"
RESULT = HERE / "results/phase114_isamore_crossbeam_bridge_audit.json"
TAG_BLOBS = {
    "Cargo.toml": "43625de58a1c3d002bcf2f9385f7fa6857895d3b",
    "src/lib.rs": "1230e5dce61f01ece377709c4e73723a72ae51d9",
    "crossbeam-queue/Cargo.toml": (
        "8a2d7cc90aed9c982ab363e4f4455e2535183ebb"
    ),
    "crossbeam-queue/src/lib.rs": (
        "c1661872689f671b065738c66a2d9575f8542116"
    ),
    "crossbeam-queue/src/array_queue.rs": (
        "0d2569d4d310bca82c1140571f839413d9ae31a8"
    ),
    "crossbeam-queue/src/seg_queue.rs": (
        "ad8f9c1ab947a336ac30e0efe05ff2be9bf39169"
    ),
}
LOCKED_ARCHIVES = {
    "crossbeam-channel-0.5.15.crate": (
        "82b8f8f868b36967f9606790d1903570de9ceaf870a7bf9fbbd3016d636a2cb2"
    ),
    "crossbeam-deque-0.8.6.crate": (
        "9dd111b7b7f7d55b72c0a6ae361660ee5853c9af73f70c3c2ef6858b950e2e51"
    ),
    "crossbeam-epoch-0.9.18.crate": (
        "5b82ac4a3c2ca9c3460964f020e1402edd5753411d7737aa39c3714ad1b5420e"
    ),
    "crossbeam-utils-0.8.21.crate": (
        "d0a5c400df2834b80a4c3327b3aad3a4c4cd4de0629063962b03235697506a28"
    ),
}


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_blob(path: pathlib.Path) -> str:
    raw = path.read_bytes()
    return hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()


def tree_digest(path: pathlib.Path) -> tuple[str, int]:
    rows = []
    for item in sorted(value for value in path.rglob("*") if value.is_file()):
        rows.append(
            {
                "path": str(item.relative_to(path)),
                "sha256": sha256(item),
                "bytes": item.stat().st_size,
            }
        )
    return hashlib.sha256(canonical(rows).encode()).hexdigest(), len(rows)


def main() -> None:
    prior = json.loads(PRIOR.read_text())
    if not (
        prior["next_build_stop"]["package"] == "crossbeam"
        and prior["control_executed"] is False
    ):
        raise RuntimeError("prior Crossbeam stop changed")
    lock = tomllib.loads((SOURCE / "Cargo.lock").read_text())
    locked = {
        (row["name"], row["version"]): row.get("checksum")
        for row in lock["package"]
    }
    tag_records = []
    for relative, expected in TAG_BLOBS.items():
        path = VENDOR / relative
        actual = git_blob(path)
        if actual != expected:
            raise RuntimeError(f"Crossbeam tag source mismatch: {relative}")
        tag_records.append(
            {
                "path": str(path.relative_to(HERE)),
                "git_blob_sha1": actual,
                "sha256": sha256(path),
            }
        )

    cache = pathlib.Path.home() / ".cargo/registry/cache"
    archive_records = []
    for filename, checksum in LOCKED_ARCHIVES.items():
        matches = list(cache.rglob(filename))
        if len(matches) != 1 or sha256(matches[0]) != checksum:
            raise RuntimeError(f"locked Crossbeam archive mismatch: {filename}")
        name_version = filename.removesuffix(".crate")
        name, version = name_version.rsplit("-", 1)
        if locked.get((name, version)) != checksum:
            raise RuntimeError(f"Crossbeam lock checksum mismatch: {filename}")
        tree_name = name
        digest, files = tree_digest(VENDOR / tree_name)
        archive_records.append(
            {
                "package": name,
                "version": version,
                "archive_sha256": checksum,
                "locked_checksum": checksum,
                "copied_tree_sha256": digest,
                "copied_tree_files": files,
            }
        )

    cargo = shutil.which("cargo")
    if cargo is None:
        raise RuntimeError("cargo unavailable")
    receipt = run_metered_tree(
        [
            str(pathlib.Path(cargo).absolute()),
            "--config",
            'patch.crates-io.colored.path="../vendor/colored-3.1.1"',
            "--config",
            'patch.crates-io.crossbeam.path="../vendor/crossbeam-0.8.4"',
            "check",
            "--locked",
            "--lib",
        ],
        cwd=SOURCE,
        wall_limit_seconds=90,
        cpu_limit_seconds=85,
        rss_limit_kib=2_000_000,
        environment={
            "RUSTUP_TOOLCHAIN": "stable",
            "CARGO_NET_OFFLINE": "true",
            "CARGO_TERM_COLOR": "never",
            "RUST_BACKTRACE": "0",
        },
    )
    next_stop = (
        receipt["returncode"] != 0
        and receipt["termination"] == "natural"
        and "no matching package named `csv` found" in receipt["stderr_text"]
    )
    crossbeam_stop_cleared = (
        "no matching package named `crossbeam` found"
        not in receipt["stderr_text"]
    )
    if not next_stop or not crossbeam_stop_cleared:
        raise RuntimeError(
            "Crossbeam bridge did not advance expected stop: "
            + receipt["stderr_text"]
        )
    payload = {
        "version": "FOUNDRY_ISAMORE_CROSSBEAM_BRIDGE_AUDIT_V1",
        "status": "ISAMORE_CROSSBEAM_CLOSURE_ADVANCES_STOP",
        "bridge": {
            "package": "crossbeam",
            "version": "0.8.4",
            "repository": "crossbeam-rs/crossbeam",
            "root_tag": "crossbeam-0.8.4",
            "queue_tag": "crossbeam-queue-0.3.12",
            "official_tag_records": tag_records,
            "locked_cached_archive_records": archive_records,
            "root_and_queue_crates_io_checksums_authenticated": False,
            "classification": "MIXED_OFFICIAL_TAG_AND_LOCKED_ARCHIVE_BRIDGE",
        },
        "receipt": receipt,
        "checks": {
            "prior_crossbeam_stop_authenticated": True,
            "root_and_queue_official_tag_source_exact": True,
            "four_cached_archive_checksums_match_lock": True,
            "crossbeam_stop_cleared": crossbeam_stop_cleared,
            "next_missing_package_authenticated": next_stop,
            "algorithm_compilation_reached": False,
            "algorithm_execution_reached": False,
        },
        "next_build_stop": {
            "class": "MISSING_OFFLINE_REGISTRY_PACKAGE",
            "package": "csv",
            "authenticated_by_cargo": True,
        },
        "control_executed": False,
        "conformance_executed": False,
        "source_faithful_controls_reproduced": 3,
        "controls_required": 4,
        "P1_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
        "claim_boundary": (
            "The Crossbeam bridge combines exact official-tag root/queue "
            "source with four locked, checksum-matching cached crate archives "
            "and advances the stop to csv. Root and queue crates.io checksums "
            "remain unauthenticated; no ISAMORE algorithm compiled or ran."
        ),
        "next_action": (
            "recover locked csv 1.4.0 and its missing closure, preserving the "
            "same evidence distinction between crates.io checksum identity "
            "and official-tag source"
        ),
    }
    if RESULT.exists():
        frozen = json.loads(RESULT.read_text(encoding="utf-8"))
        frozen_receipt = frozen.get("receipt", {})
        frozen_semantics = dict(frozen)
        current_semantics = dict(payload)
        frozen_semantics.pop("receipt", None)
        current_semantics.pop("receipt", None)
        frozen_stop_is_valid = (
            frozen_receipt.get("returncode") != 0
            and frozen_receipt.get("termination") == "natural"
            and "no matching package named `csv` found"
            in frozen_receipt.get("stderr_text", "")
            and "no matching package named `crossbeam` found"
            not in frozen_receipt.get("stderr_text", "")
        )
        if (
            frozen_semantics != current_semantics
            or not frozen_stop_is_valid
        ):
            raise RuntimeError(
                "rerun disagrees with frozen Crossbeam bridge evidence"
            )
        evidence_mode = "VERIFY_FROZEN"
    else:
        RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
        evidence_mode = "CREATE"
    print(
        "FOUNDRY_PHASE114_ISAMORE_CROSSBEAM_BRIDGE"
        f" status={payload['status']}"
        " crossbeam=MIXED_AUTHENTICATED next_stop=csv"
        " compiled=false executed=false controls=3/4 P1=false"
        f" evidence={evidence_mode}"
    )


if __name__ == "__main__":
    main()
