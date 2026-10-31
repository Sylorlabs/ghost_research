#!/usr/bin/env python3
"""Authenticate and compile exact divrem source without inflating ISAMORE."""

from __future__ import annotations

import hashlib
import json
import pathlib
import shutil
import tempfile
import tomllib

from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
SOURCE = HERE / "external_controls/isamore/source"
VENDOR = HERE / "external_controls/isamore/vendor"
DIVREM = VENDOR / "divrem-1.0.0"
PRIOR = HERE / "results/phase125_isamore_kiddo_root_acquisition_channel_audit.json"
RESULT = HERE / "results/phase126_isamore_divrem_family_bridge_audit.json"
BLOBS = {
    "Cargo.toml": "319b7f84f312675f19a94d2225d3bbcd7a1410b5",
    "src/lib.rs": "48ea5ef7c6dce05a7dd20453791d8e68c7ad4f9b",
    "src/macros.rs": "fa7e52b5aba6eebc8a0f1684e29b72de0954804a",
    "src/ceil.rs": "2b94af984d51e0a9b477557e7a86813c79af5cd8",
    "src/euclid.rs": "2cc3fd9e641a2d90bd2d4cb5b2bb5d0ba7e0df51",
    "src/floor.rs": "42d903809dc67d5ef84b4f544feda8c84e83a219",
    "src/trunc.rs": "22dbebd60d8b5ca144da5cc4b88c2ae9f15ff240",
}


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_blob(path: pathlib.Path) -> str:
    raw = path.read_bytes()
    return hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()


def patched_isamore_args(cargo: str) -> list[str]:
    args = [cargo]
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
        "divrem": "../vendor/divrem-1.0.0",
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
    return args + ["check", "--locked", "--lib"]


def main() -> None:
    prior = json.loads(PRIOR.read_text())
    if not (
        prior["status"]
        == "ISAMORE_KIDDO_ROOT_AVAILABLE_CHANNELS_AUDITED_NO_SOURCE"
        and prior["checks"]["kiddo_root_source_acquired"] is False
        and prior["next_build_stop"]["package"] == "kiddo"
    ):
        raise RuntimeError("prior kiddo acquisition boundary changed")

    records = []
    for relative, expected in BLOBS.items():
        path = DIVREM / relative
        actual = git_blob(path)
        if actual != expected:
            raise RuntimeError(f"divrem source mismatch: {relative}")
        records.append(
            {
                "path": str(path.relative_to(HERE)),
                "repository": "letheed/divrem",
                "revision": "1.0.0",
                "git_blob_sha1": actual,
                "sha256": sha256(path),
            }
        )
    manifest = tomllib.loads((DIVREM / "Cargo.toml").read_text())
    if (
        manifest["package"]["name"] != "divrem"
        or manifest["package"]["version"] != "1.0.0"
    ):
        raise RuntimeError("divrem manifest identity mismatch")

    cargo = shutil.which("cargo")
    if cargo is None:
        raise RuntimeError("cargo unavailable")
    cargo = str(pathlib.Path(cargo).absolute())
    environment = {
        "RUSTUP_TOOLCHAIN": "stable",
        "CARGO_NET_OFFLINE": "true",
        "CARGO_TERM_COLOR": "never",
        "RUST_BACKTRACE": "0",
    }
    with tempfile.TemporaryDirectory(prefix="foundry-divrem-") as tmp:
        copied = pathlib.Path(tmp) / "divrem-1.0.0"
        shutil.copytree(DIVREM, copied)
        compile_receipt = run_metered_tree(
            [cargo, "check", "--offline", "--lib"],
            cwd=copied,
            wall_limit_seconds=60,
            cpu_limit_seconds=55,
            rss_limit_kib=1_000_000,
            environment={
                **environment,
                "CARGO_TARGET_DIR": str(pathlib.Path(tmp) / "target"),
            },
        )
    if (
        compile_receipt["returncode"] != 0
        or compile_receipt["termination"] != "natural"
    ):
        raise RuntimeError("exact divrem source did not compile")

    resolver_receipt = run_metered_tree(
        patched_isamore_args(cargo),
        cwd=SOURCE,
        wall_limit_seconds=90,
        cpu_limit_seconds=85,
        rss_limit_kib=2_000_000,
        environment=environment,
    )
    stop_unchanged = (
        resolver_receipt["returncode"] != 0
        and resolver_receipt["termination"] == "natural"
        and "no matching package named `kiddo` found"
        in resolver_receipt["stderr_text"]
    )
    if not stop_unchanged:
        raise RuntimeError("divrem bridge produced unexpected resolver result")

    payload = {
        "version": "FOUNDRY_ISAMORE_DIVREM_FAMILY_BRIDGE_AUDIT_V1",
        "status": "ISAMORE_DIVREM_EXACT_TAG_AUTHENTICATED_NO_STOP_ADVANCE",
        "bridge": {
            "package": "divrem",
            "version": "1.0.0",
            "repository": "letheed/divrem",
            "revision": "1.0.0",
            "classification": "EXACT_OFFICIAL_RELEASE_TAG",
            "source_records": records,
            "record_count": len(records),
            "crates_io_tarball_checksum_authenticated": False,
        },
        "compile_receipt": compile_receipt,
        "resolver_receipt": resolver_receipt,
        "checks": {
            "manifest_version_matches_lock": True,
            "all_source_records_match_upstream": True,
            "source_compilation_passed": True,
            "resolver_stop_unchanged": True,
            "kiddo_root_source_acquired": False,
            "isamore_algorithm_compilation_reached": False,
            "isamore_algorithm_execution_reached": False,
        },
        "accumulated_kiddo_family": {
            "packages_bridged": 4,
            "packages_required": 8,
            "source_records_authenticated": 20,
            "source_records_expected": 20,
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
            "divrem 1.0.0 matches seven blobs at its exact official release "
            "tag and compiles independently. The ISAMORE resolver still stops "
            "at the absent kiddo root, so no ISAMORE algorithm compiled or "
            "executed and no fourth control is claimed."
        ),
        "next_action": (
            "authenticate the remaining exact kiddo math/data-structure "
            "sources: az 1.3.0, fixed 1.30.0, and sorted-vec 0.8.10"
        ),
    }
    if RESULT.exists():
        frozen = json.loads(RESULT.read_text())
        current_semantics = dict(payload)
        frozen_semantics = dict(frozen)
        current_semantics.pop("compile_receipt")
        current_semantics.pop("resolver_receipt")
        frozen_compile = frozen_semantics.pop("compile_receipt")
        frozen_resolver = frozen_semantics.pop("resolver_receipt")
        valid_receipts = (
            frozen_compile.get("returncode") == 0
            and frozen_compile.get("termination") == "natural"
            and frozen_resolver.get("returncode") != 0
            and "no matching package named `kiddo` found"
            in frozen_resolver.get("stderr_text", "")
        )
        if current_semantics != frozen_semantics or not valid_receipts:
            raise RuntimeError("rerun disagrees with frozen divrem bridge")
        mode = "VERIFY_FROZEN"
    else:
        RESULT.write_text(canonical(payload) + "\n")
        mode = "CREATE"
    print(
        "FOUNDRY_PHASE126_ISAMORE_DIVREM_FAMILY"
        " status=EXACT_TAG_AUTHENTICATED_NO_ADVANCE records=7"
        " compiled=true stop=kiddo isamore_compiled=false"
        " executed=false P1=false"
        f" evidence={mode}"
    )


if __name__ == "__main__":
    main()
