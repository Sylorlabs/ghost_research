#!/usr/bin/env python3
"""Advance ISAMORE through four exact official-tag indicatif packages."""

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
PRIOR = HERE / "results/phase121_isamore_indicatif_closure_census.json"
RESULT = HERE / "results/phase122_isamore_indicatif_family_bridge_audit.json"
PACKAGES = {
    "indicatif": ("0.17.11", "indicatif-0.17.11", "console-rs/indicatif", "0.17.11"),
    "console": ("0.15.11", "console-0.15.11", "console-rs/console", "0.15.11"),
    "number_prefix": (
        "0.4.0",
        "number_prefix-0.4.0",
        "ogham/rust-number-prefix",
        "v0.4.0",
    ),
    "encode_unicode": (
        "1.0.0",
        "encode_unicode-1.0.0",
        "tormol/encode_unicode",
        "v1.0.0",
    ),
}
BLOBS = {
    "indicatif-0.17.11/Cargo.toml": "fd882c49bac19f86ce3ec65abbc11d361f9f2592",
    "indicatif-0.17.11/src/lib.rs": "578c39c615a693cef1d256d818cc556ff8257356",
    "indicatif-0.17.11/src/draw_target.rs": "cffdf1234bc01cb50b45a267b9dfafafff849a38",
    "indicatif-0.17.11/src/format.rs": "3325368c61d7a79d197584557d470bb9f5564b8a",
    "indicatif-0.17.11/src/in_memory.rs": "046ae14a09f1d6ac7933b755b7f316eba298c24a",
    "indicatif-0.17.11/src/iter.rs": "8861db52a05ace6be7c5ee6b0cd3df3bfa5dc8b8",
    "indicatif-0.17.11/src/multi.rs": "c7cd1eb18b9e0c2464a123a2c0d0b1fcd331be7a",
    "indicatif-0.17.11/src/progress_bar.rs": "4f4d1816d43f0e56dd5312c0b97a1ea2021123f8",
    "indicatif-0.17.11/src/rayon.rs": "1c8e844f5f775a5dfc1b87ea1ffd9c1ee8b0c5eb",
    "indicatif-0.17.11/src/state.rs": "ba472122fea7d3aa53dc15a4de24c19c62410091",
    "indicatif-0.17.11/src/style.rs": "cc961b0a499e6236d4ede9af76ca16f0ce732df0",
    "indicatif-0.17.11/src/term_like.rs": "b489b655dc2b8012428e14625f444df31282e70d",
    "console-0.15.11/Cargo.toml": "81989828f88248cb0f75e543a5601a50bc63e8df",
    "console-0.15.11/src/lib.rs": "2d3114b078000384216b4826c0e8897476c4d847",
    "console-0.15.11/src/ansi.rs": "371ca541c19c15596385dec3c1bb07b851fcd99a",
    "console-0.15.11/src/common_term.rs": "e3c119069b3ce4ed523de4eb75514d44003564b3",
    "console-0.15.11/src/kb.rs": "2a0f61edf927f0471df43e0ba9c4ccbb43d71e11",
    "console-0.15.11/src/term.rs": "6f44f7d08f18fd1601dcb3a3349e1d7833fb49f7",
    "console-0.15.11/src/unix_term.rs": "0f7ac00d76c752d8a142a59045d2e191f68511e4",
    "console-0.15.11/src/utils.rs": "a6cf37d6101695e0f6863daaeff4dc018ccdd8d3",
    "console-0.15.11/src/wasm_term.rs": "e967d9a0e39f1f416abe05f2a0e32e5d2b67a483",
    "console-0.15.11/src/windows_term/mod.rs": "2c71f4f7c6163d82285ccf2b4ac12d9c5e6df334",
    "console-0.15.11/src/windows_term/colors.rs": "731e9e017aa79af66c073a713cd4fe528881ca5e",
    "number_prefix-0.4.0/Cargo.toml": "d2f71e2d1e980ee974138dee96bcbdc114b78214",
    "number_prefix-0.4.0/src/lib.rs": "20741e2035d5bde7879b64a5ea733542f5fba05c",
    "number_prefix-0.4.0/src/parse.rs": "cfb37af4a6589373e0c43ee7a2623aa6320be83f",
    "encode_unicode-1.0.0/Cargo.toml": "3bc0d33d6385342cae35b28b294047ef204f8ed7",
    "encode_unicode-1.0.0/src/lib.rs": "939125d1c4314aa1552fcc3cea938a39322d631b",
    "encode_unicode-1.0.0/src/errors.rs": "13b6ca5fa66bcbd1ce9f1e0673e8c76628af3c6e",
    "encode_unicode-1.0.0/src/traits.rs": "53b1211e07174d1e35c0472e9105edf45f1abd35",
    "encode_unicode-1.0.0/src/utf8_char.rs": "58eef04fcda8dcf96a9946318ea75e44e9f38836",
    "encode_unicode-1.0.0/src/utf8_iterators.rs": "b37c6877335380b168568292cb06d7cbb94fe2d9",
    "encode_unicode-1.0.0/src/utf16_char.rs": "a16da7bc4fb4be07e3c904c88b0eacd0fd37356c",
    "encode_unicode-1.0.0/src/utf16_iterators.rs": "30dcd80dbd5069457c2bb5005aec74d2aadd7f08",
    "encode_unicode-1.0.0/src/decoding_iterators.rs": "92bc06087cc40d0e147d1a2d7af58f26e0184d73",
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
        prior["summary"] == {
            "locked_packages": 31,
            "exact_cached_archives": 18,
            "missing_exact_archives": 13,
        }
        and prior["build_stop_after_phase"] == "indicatif"
    ):
        raise RuntimeError("prior indicatif census changed")

    records = []
    for relative, expected in BLOBS.items():
        path = VENDOR / relative
        actual = git_blob(path)
        if actual != expected:
            raise RuntimeError(f"official-tag source mismatch: {relative}")
        package_dir = relative.split("/", 1)[0]
        package = next(
            name for name, (_, directory, _, _) in PACKAGES.items()
            if directory == package_dir
        )
        records.append(
            {
                "path": str(path.relative_to(HERE)),
                "package": package,
                "tag": PACKAGES[package][3],
                "git_blob_sha1": actual,
                "sha256": sha256(path),
            }
        )
    for package, (version, directory, _, _) in PACKAGES.items():
        manifest = tomllib.loads((VENDOR / directory / "Cargo.toml").read_text())
        if (
            manifest["package"]["name"] != package
            or manifest["package"]["version"] != version
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
        and "no matching package named `kiddo` found" in receipt["stderr_text"]
    )
    cleared = "no matching package named `indicatif` found" not in receipt["stderr_text"]
    if not next_stop or not cleared:
        raise RuntimeError("indicatif family did not advance expected stop")

    payload = {
        "version": "FOUNDRY_ISAMORE_INDICATIF_FAMILY_BRIDGE_AUDIT_V1",
        "status": "ISAMORE_INDICATIF_FAMILY_ADVANCES_STOP",
        "bridge": {
            "packages": {
                name: {
                    "version": version,
                    "repository": repository,
                    "tag": tag,
                }
                for name, (version, _, repository, tag) in PACKAGES.items()
            },
            "source_records": records,
            "record_count": len(records),
            "all_release_tags_resolved": True,
            "crates_io_tarball_checksums_authenticated": False,
            "classification": "EXACT_OFFICIAL_RELEASE_TAG_BUILD_SURFACES",
        },
        "receipt": receipt,
        "checks": {
            "all_manifest_versions_match_lock": True,
            "all_source_records_match_official_tags": True,
            "indicatif_stop_cleared": cleared,
            "next_missing_package_authenticated": next_stop,
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
            "Four indicatif-family packages match exact official release tags "
            "across 35 Git blobs and advance the identical offline resolver to "
            "kiddo. Tag source is not crates.io archive identity, and no "
            "algorithm compiled or executed."
        ),
        "next_action": "audit the exact locked kiddo closure",
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
            raise RuntimeError("rerun disagrees with frozen indicatif bridge")
        mode = "VERIFY_FROZEN"
    else:
        RESULT.write_text(canonical(payload) + "\n")
        mode = "CREATE"
    print(
        "FOUNDRY_PHASE122_ISAMORE_INDICATIF_FAMILY"
        " status=ADVANCES_STOP packages=4 records=35 next_stop=kiddo"
        " compiled=false executed=false P1=false"
        f" evidence={mode}"
    )


if __name__ == "__main__":
    main()
