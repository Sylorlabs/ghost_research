#!/usr/bin/env python3
"""Advance ISAMORE through all three exact env_logger release-tag roots."""

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
PRIOR = HERE / "results/phase117_isamore_env_logger_closure_census.json"
RESULT = HERE / "results/phase118_isamore_env_logger_roots_bridge_audit.json"
COMMON_07 = {
    "Cargo.toml": "148543b5b1e5ad8f9401cab7e07884ac45cceb3e",
    "src/lib.rs": "415183600b268af5a539c3d9b67b94a2240d81b6",
    "src/filter/mod.rs": "a994f4dc6cd69d8d15a314cd7e12f9e9fa71a86b",
    "src/filter/string.rs": "ea476e42f934fd80d1314f73737e320994281072",
    "src/filter/regex.rs": "fb21528a121614290b05e5dc61943916b46e1ecf",
    "src/fmt/mod.rs": "e699e214d64b0aa76da8066a76eadaee21e04919",
    "src/fmt/humantime/mod.rs": "ac23ae2493f36637c5532bd008e5f755bc65ebfa",
    "src/fmt/humantime/extern_impl.rs": "19dec1b65d39065fcff5d88a8988619f3c08c1fc",
    "src/fmt/humantime/shim_impl.rs": "906bf9e4c1a6a96f284c413b450142f2621ce334",
    "src/fmt/writer/mod.rs": "6ee63a39811c1d979b4274019a8563b6b8c81163",
    "src/fmt/writer/atty.rs": "f6718413f0d68cf09b15443134734529ca095903",
    "src/fmt/writer/termcolor/mod.rs": "f3e6768cd05103cbdd21c0dbcd743c952550c2f9",
    "src/fmt/writer/termcolor/extern_impl.rs": "2d38e375aaf412b45f85061313b9b2818ce96ad4",
    "src/fmt/writer/termcolor/shim_impl.rs": "563f8ad4ffd797313478a2cec3110dedc76ef970",
}
COMMON_09 = {
    "Cargo.toml": "d44b8cd83bb95cb60f4362c479f457ab8a698feb",
    "src/lib.rs": "642b731af3f2364abdbdcaee9925038ba3ae7e66",
    "src/filter/mod.rs": "a02d6bc1f0c53283b3a5dea3867d1191e581ebc9",
    "src/filter/string.rs": "ea476e42f934fd80d1314f73737e320994281072",
    "src/filter/regex.rs": "fb21528a121614290b05e5dc61943916b46e1ecf",
    "src/fmt/mod.rs": "1677887a6636cbf437f7b7a6be438c55ceca5b4f",
    "src/fmt/humantime/mod.rs": "ac23ae2493f36637c5532bd008e5f755bc65ebfa",
    "src/fmt/humantime/extern_impl.rs": "bdf165c4eb246c15538553e60c9191510f5220bb",
    "src/fmt/humantime/shim_impl.rs": "906bf9e4c1a6a96f284c413b450142f2621ce334",
    "src/fmt/writer/mod.rs": "2b56772e5479219c78078a586a4716ab6815d907",
    "src/fmt/writer/atty.rs": "343539c15773d64d9a4201c74327e5097f02bc43",
    "src/fmt/writer/termcolor/mod.rs": "f3e6768cd05103cbdd21c0dbcd743c952550c2f9",
    "src/fmt/writer/termcolor/extern_impl.rs": "fbe37a77bf3f5755c12e0b1a317ee3c1f09c23c9",
    "src/fmt/writer/termcolor/shim_impl.rs": "0705770c95fe2000a8eeb075439c50eb5b8639d4",
}
COMMON_011 = {
    "Cargo.toml": "b33c11736647f32f62ed48e89807dacb810b0dd2",
    "src/lib.rs": "7770bf1c4a3f02ccab0564c267d783acd381227d",
    "src/logger.rs": "1ecfcc8445ad60895fea3da1a5bd4d1eda8cbfdf",
    "src/writer/mod.rs": "61e9255c6414da502a136cb2ec427a8c72ac7052",
    "src/writer/buffer.rs": "f2661eea9a76a7a7e07640b2aa483b77995a3bab",
    "src/writer/target.rs": "a1220ffeee3e366c2b207eadbbd3cf11a8a5fab2",
    "src/fmt/mod.rs": "398dab7024838241343ae022b03dc0ff020f3ac8",
    "src/fmt/humantime.rs": "a6bab88e8b46518fecc9938ac8735c5831aa867b",
    "src/fmt/kv.rs": "cbb7daeca90ddae04f0af80df8df77c2df6ec4d0",
}
ROOTS = (
    ("0.7.1", "v0.7.1", COMMON_07),
    ("0.9.3", "v0.9.3", COMMON_09),
    ("0.11.9", "v0.11.9", COMMON_011),
)


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
        prior["summary"]["root_versions"] == 3
        and prior["single_version_patch_rejected"] is True
        and prior["build_stop_after_phase"] == "env_logger"
    ):
        raise RuntimeError("prior env_logger census changed")
    records = []
    for version, tag, files in ROOTS:
        root = VENDOR / f"env_logger-{version}"
        manifest = tomllib.loads((root / "Cargo.toml").read_text())
        if manifest["package"]["version"] != version:
            raise RuntimeError(f"env_logger manifest mismatch: {version}")
        for relative, expected in files.items():
            path = root / relative
            actual = git_blob(path)
            if actual != expected:
                raise RuntimeError(f"env_logger tag blob mismatch: {version}/{relative}")
            records.append(
                {
                    "version": version,
                    "tag": tag,
                    "path": str(path.relative_to(HERE)),
                    "git_blob_sha1": actual,
                    "sha256": sha256(path),
                }
            )

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
    next_stop = (
        receipt["returncode"] != 0
        and receipt["termination"] == "natural"
        and "no matching package named `graphviz-rust` found"
        in receipt["stderr_text"]
    )
    roots_cleared = "no matching package named `env_logger` found" not in receipt["stderr_text"]
    if not next_stop or not roots_cleared:
        raise RuntimeError("env_logger roots did not advance expected stop")
    payload = {
        "version": "FOUNDRY_ISAMORE_ENV_LOGGER_ROOTS_BRIDGE_AUDIT_V1",
        "status": "ISAMORE_ENV_LOGGER_ROOTS_ADVANCE_STOP",
        "bridge": {
            "repository": "rust-cli/env_logger",
            "versions": ["0.7.1", "0.9.3", "0.11.9"],
            "official_tag_records": records,
            "record_count": len(records),
            "multi_version_aliases": [
                "env_logger_07",
                "env_logger_09",
                "env_logger_011",
            ],
            "crates_io_tarball_checksums_authenticated": False,
            "classification": "THREE_EXACT_OFFICIAL_TAG_ROOTS",
        },
        "receipt": receipt,
        "checks": {
            "all_three_manifest_versions_match_lock": True,
            "all_source_records_exact_to_official_tags": True,
            "single_version_substitution": False,
            "env_logger_stop_cleared": roots_cleared,
            "next_missing_package_authenticated": next_stop,
            "algorithm_compilation_reached": False,
            "algorithm_execution_reached": False,
        },
        "next_build_stop": {
            "class": "MISSING_OFFLINE_REGISTRY_PACKAGE",
            "package": "graphviz-rust",
            "authenticated_by_cargo": True,
        },
        "control_executed": False,
        "source_faithful_controls_reproduced": 3,
        "controls_required": 4,
        "P1_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
        "claim_boundary": (
            "All three exact official-tag env_logger roots mount through Cargo "
            "package aliases and advance resolution to graphviz-rust. This is "
            "not crates.io checksum identity, compilation, or control execution."
        ),
        "next_action": "audit the exact locked graphviz-rust closure",
    }
    if RESULT.exists():
        frozen = json.loads(RESULT.read_text())
        frozen_receipt = frozen.pop("receipt", {})
        current_receipt = payload.pop("receipt")
        valid_frozen = (
            frozen_receipt.get("termination") == "natural"
            and "no matching package named `graphviz-rust` found"
            in frozen_receipt.get("stderr_text", "")
        )
        payload["receipt"] = current_receipt
        frozen["receipt"] = frozen_receipt
        current_semantics = dict(payload)
        current_semantics.pop("receipt")
        frozen_semantics = dict(frozen)
        frozen_semantics.pop("receipt")
        if current_semantics != frozen_semantics or not valid_frozen:
            raise RuntimeError("rerun disagrees with frozen env_logger bridge")
        mode = "VERIFY_FROZEN"
    else:
        RESULT.write_text(canonical(payload) + "\n")
        mode = "CREATE"
    print(
        "FOUNDRY_PHASE118_ISAMORE_ENV_LOGGER_ROOTS"
        f" status=ADVANCES_STOP roots=3 records={len(records)}"
        " next_stop=graphviz-rust compiled=false executed=false P1=false"
        f" evidence={mode}"
    )


if __name__ == "__main__":
    main()
