#!/usr/bin/env python3
"""Authenticate three exact kiddo-family source surfaces without inflating progress."""

from __future__ import annotations

import hashlib
import json
import pathlib
import shutil
import tomllib

from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
SOURCE = HERE / "external_controls/isamore/source"
VENDOR = HERE / "external_controls/isamore/vendor"
PRIOR = HERE / "results/phase123_isamore_kiddo_closure_census.json"
RESULT = HERE / "results/phase124_isamore_kiddo_partial_family_bridge_audit.json"
PACKAGES = {
    "array-init": {
        "version": "2.1.0",
        "directory": "array-init-2.1.0",
        "repository": "Manishearth/array-init",
        "revision": "60635047ab2800832319829840c68df03c39945b",
        "classification": "PINNED_OFFICIAL_PUBLISH_COMMIT",
    },
    "ordered-float": {
        "version": "5.1.0",
        "directory": "ordered-float-5.1.0",
        "repository": "reem/rust-ordered-float",
        "revision": "v5.1.0",
        "classification": "EXACT_OFFICIAL_RELEASE_TAG",
    },
    "cmov": {
        "version": "0.4.6",
        "directory": "cmov-0.4.6",
        "repository": "RustCrypto/utils",
        "revision": "cmov-v0.4.6",
        "classification": "EXACT_OFFICIAL_RELEASE_TAG",
    },
}
BLOBS = {
    "array-init-2.1.0/Cargo.toml": "da9129e3a96be3d1dec0092201743ba625468c8c",
    "array-init-2.1.0/src/lib.rs": "6a0f50fcda29c49d8ab8b2cd2e492ac8b1323b3b",
    "ordered-float-5.1.0/Cargo.toml": "c13504e1c7dcca1b0f9465043e158a87fbd7e5dc",
    "ordered-float-5.1.0/src/lib.rs": "dc44a4d7f74f81891ca96980774dbcffd1002bf3",
    "cmov-0.4.6/Cargo.toml": "eacd9accc544d8f0c1c320904584ebb7088e0fb7",
    "cmov-0.4.6/README.md": "481c972820b4fdd36c1bc7f2a979562daa13adec",
    "cmov-0.4.6/src/lib.rs": "041d03a5517da9c11034de9f643e56f1dcb58458",
    "cmov-0.4.6/src/utils.rs": "21c8365571334d17f1231c87614b2a9c9b5e7b7b",
    "cmov-0.4.6/src/aarch64.rs": "68c503b547da1b75820a5b8a7ed5a10a705c348e",
    "cmov-0.4.6/src/array.rs": "5996c5df8109d29112e76a9bf57be05dbd5ee53d",
    "cmov-0.4.6/src/portable.rs": "9b1bbc09b217594939fbaf8c4e452225a0f4f802",
    "cmov-0.4.6/src/slice.rs": "0868e52fd751a0de897e8524d62c6a7d2928576b",
    "cmov-0.4.6/src/x86.rs": "bb6a86e48067785a81a7cee1c4f7668ceb60b606",
}


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_blob(path: pathlib.Path) -> str:
    raw = path.read_bytes()
    return hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()


def main() -> None:
    prior = json.loads(PRIOR.read_text())
    if not (
        prior["status"] == "ISAMORE_KIDDO_CLOSURE_AUTHENTICATED_INCOMPLETE"
        and prior["summary"]["locked_packages"] == 56
        and prior["summary"]["missing_exact_archives"] == 22
        and prior["build_stop_after_phase"] == "kiddo"
    ):
        raise RuntimeError("prior kiddo census changed")

    records = []
    for relative, expected in BLOBS.items():
        path = VENDOR / relative
        actual = git_blob(path)
        if actual != expected:
            raise RuntimeError(f"kiddo-family source mismatch: {relative}")
        directory = relative.split("/", 1)[0]
        package = next(
            name
            for name, row in PACKAGES.items()
            if row["directory"] == directory
        )
        records.append(
            {
                "path": str(path.relative_to(HERE)),
                "package": package,
                "repository": PACKAGES[package]["repository"],
                "revision": PACKAGES[package]["revision"],
                "git_blob_sha1": actual,
                "sha256": sha256(path),
            }
        )
    for package, row in PACKAGES.items():
        manifest = tomllib.loads(
            (VENDOR / row["directory"] / "Cargo.toml").read_text()
        )
        if (
            manifest["package"]["name"] != package
            or manifest["package"]["version"] != row["version"]
        ):
            raise RuntimeError(f"manifest identity mismatch: {package}")

    cargo = shutil.which("cargo")
    if cargo is None:
        raise RuntimeError("cargo unavailable")
    args = [str(pathlib.Path(cargo).absolute())]
    paths = {
        "colored": "../vendor/colored-3.1.1",
        "crossbeam": "../vendor/crossbeam-0.8.4",
        "csv": "../vendor/csv-1.4.0",
        "csv-core": "../vendor/csv-1.4.0/csv-core",
        "itoa": "../vendor/itoa-1.0.17",
        "quote": "../vendor/quote-1.0.44",
        "graphviz-rust": "../vendor/graphviz-rust-0.8.0",
        "dot-generator": "../vendor/graphviz-rust-0.8.0/dot-generator",
        "dot-structures": "../vendor/graphviz-rust-0.8.0/dot-structures",
        "into-attr": "../vendor/graphviz-rust-0.8.0/into-attr",
        "into-attr-derive": "../vendor/graphviz-rust-0.8.0/into-attr-derive",
        "indicatif": "../vendor/indicatif-0.17.11",
        "console": "../vendor/console-0.15.11",
        "number_prefix": "../vendor/number_prefix-0.4.0",
        "encode_unicode": "../vendor/encode_unicode-1.0.0",
        "array-init": "../vendor/array-init-2.1.0",
        "ordered-float": "../vendor/ordered-float-5.1.0",
        "cmov": "../vendor/cmov-0.4.6",
    }
    for name, path in paths.items():
        args += ["--config", f'patch.crates-io.{name}.path="{path}"']
    for alias, version in (
        ("env_logger_07", "0.7.1"),
        ("env_logger_09", "0.9.3"),
        ("env_logger_011", "0.11.9"),
    ):
        args += [
            "--config",
            f'patch.crates-io.{alias}.package="env_logger"',
            "--config",
            f'patch.crates-io.{alias}.path="../vendor/env_logger-{version}"',
        ]
    args += ["check", "--locked", "--lib"]
    receipt = run_metered_tree(
        args,
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
    stop_unchanged = (
        receipt["returncode"] != 0
        and receipt["termination"] == "natural"
        and "no matching package named `kiddo` found" in receipt["stderr_text"]
    )
    if not stop_unchanged:
        raise RuntimeError("partial kiddo family produced unexpected resolver result")

    payload = {
        "version": "FOUNDRY_ISAMORE_KIDDO_PARTIAL_FAMILY_BRIDGE_AUDIT_V1",
        "status": "ISAMORE_KIDDO_PARTIAL_FAMILY_AUTHENTICATED_NO_STOP_ADVANCE",
        "bridge": {
            "packages": PACKAGES,
            "source_records": records,
            "record_count": len(records),
            "exact_release_tags": 2,
            "pinned_official_publish_commits": 1,
            "crates_io_tarball_checksums_authenticated": False,
        },
        "receipt": receipt,
        "checks": {
            "all_manifest_versions_match_lock": True,
            "all_source_records_match_upstream": True,
            "resolver_stop_unchanged": stop_unchanged,
            "kiddo_root_source_acquired": False,
            "algorithm_compilation_reached": False,
            "algorithm_execution_reached": False,
        },
        "next_build_stop": {
            "class": "MISSING_OFFLINE_REGISTRY_PACKAGE",
            "package": "kiddo",
            "authenticated_by_cargo": True,
        },
        "control_executed": False,
        "source_faithful_controls_reproduced": 3,
        "controls_required": 4,
        "P1_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
        "claim_boundary": (
            "Three kiddo-family packages match 13 upstream Git blobs, but the "
            "kiddo root itself remains absent and the resolver stop does not "
            "advance. Two sources are exact release tags; array-init is an "
            "exact official publish commit. No archive identity, compilation, "
            "or execution is claimed."
        ),
        "next_action": (
            "obtain an exact kiddo 5.2.4 published source surface without "
            "rewriting the upstream 5.2.1 repository manifest"
        ),
    }
    if RESULT.exists():
        frozen = json.loads(RESULT.read_text())
        frozen_receipt = frozen.get("receipt", {})
        current_semantics = dict(payload)
        frozen_semantics = dict(frozen)
        current_semantics.pop("receipt")
        frozen_semantics.pop("receipt")
        valid = (
            frozen_receipt.get("termination") == "natural"
            and "no matching package named `kiddo` found"
            in frozen_receipt.get("stderr_text", "")
        )
        if current_semantics != frozen_semantics or not valid:
            raise RuntimeError("rerun disagrees with frozen partial kiddo bridge")
        mode = "VERIFY_FROZEN"
    else:
        RESULT.write_text(canonical(payload) + "\n")
        mode = "CREATE"
    print(
        "FOUNDRY_PHASE124_ISAMORE_KIDDO_PARTIAL_FAMILY"
        " status=AUTHENTICATED_NO_ADVANCE packages=3 records=13"
        " stop=kiddo compiled=false executed=false P1=false"
        f" evidence={mode}"
    )


if __name__ == "__main__":
    main()
