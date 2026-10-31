#!/usr/bin/env python3
"""Advance ISAMORE through the pinned graphviz package family."""

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
ROOT = VENDOR / "graphviz-rust-0.8.0"
PRIOR = HERE / "results/phase119_isamore_graphviz_closure_census.json"
RESULT = HERE / "results/phase120_isamore_graphviz_family_bridge_audit.json"
ROOT_REVISION = "b11072bb9218b062099471c377d4d850f19cfe53"
DOT_STRUCTURES_REVISION = "a7c8a78dba524eec6ce36f1f2f15992f60a22f9e"
BLOBS = {
    "Cargo.toml": "813df2a76a2717ce39442a9adc5f8373ca4770d1",
    "src/lib.rs": "fdf09f6c80d7c9bffa01c96820533d48730f3c8f",
    "src/cmd.rs": "41fb50386db6a9c19481bdc7f9911eef9caf3476",
    "src/parser.rs": "6b60c1c9138e1ac2af2fb0a335d9dd799a8d6fa0",
    "src/printer.rs": "8427c944b7d37833ccf3e330bc93d113b803f60f",
    "src/attributes/mod.rs": "9043c936650c5734cb85696b23afce57cafba49e",
    "src/attributes/generate.rs": "e787d8b2f8a89c72b34cb630904a61dbbf0b47e0",
    "src/grammar/dot.pest": "22266708011701f54e9b35074e97c63909f1dd3f",
    "dot-generator/Cargo.toml": "2faa67b964fe8d05d9c3d5d7250957d19719a1cd",
    "dot-generator/src/lib.rs": "0dcb7bf8feec47fc62ff03f0dc0af0b527f4b888",
    "dot-structures/Cargo.toml": "b645933385e3cafd655ae0e06a9d25140f59e92f",
    "dot-structures/src/lib.rs": "5af8fc0df03a9444fb5ca85ad5a7509e90c74dd0",
    "into-attr/Cargo.toml": "2f056dfe2b8782cd293606f6d061793e23470217",
    "into-attr/src/lib.rs": "25c85b5e025ae38e0a5cd8b65f13e804b6757320",
    "into-attr-derive/Cargo.toml": "5918285b35bafd8efc87790f7bdac650b637c251",
    "into-attr-derive/src/lib.rs": "252b1fe11084bf59017107db9f4af34bfe4c9b48",
}
PACKAGES = {
    "graphviz-rust": ("0.8.0", "."),
    "dot-generator": ("0.2.0", "dot-generator"),
    "dot-structures": ("0.1.2", "dot-structures"),
    "into-attr": ("0.1.1", "into-attr"),
    "into-attr-derive": ("0.2.1", "into-attr-derive"),
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
        prior["summary"]["locked_packages"] == 77
        and prior["summary"]["missing_exact_archives"] == 20
        and prior["build_stop_after_phase"] == "graphviz-rust"
    ):
        raise RuntimeError("prior graphviz census changed")
    records = []
    for relative, expected in BLOBS.items():
        path = ROOT / relative
        actual = git_blob(path)
        if actual != expected:
            raise RuntimeError(f"graphviz source mismatch: {relative}")
        records.append(
            {
                "path": str(path.relative_to(HERE)),
                "revision": (
                    DOT_STRUCTURES_REVISION
                    if relative.startswith("dot-structures/")
                    else ROOT_REVISION
                ),
                "git_blob_sha1": actual,
                "sha256": sha256(path),
            }
        )
    for package, (version, relative) in PACKAGES.items():
        manifest = tomllib.loads((ROOT / relative / "Cargo.toml").read_text())
        if (
            manifest["package"]["name"] != package
            or manifest["package"]["version"] != version
        ):
            raise RuntimeError(f"graphviz manifest mismatch: {package}")

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
        and "no matching package named `indicatif` found"
        in receipt["stderr_text"]
    )
    cleared = (
        "no matching package named `graphviz-rust` found"
        not in receipt["stderr_text"]
    )
    if not next_stop or not cleared:
        raise RuntimeError("graphviz family did not advance expected stop")
    payload = {
        "version": "FOUNDRY_ISAMORE_GRAPHVIZ_FAMILY_BRIDGE_AUDIT_V1",
        "status": "ISAMORE_GRAPHVIZ_FAMILY_ADVANCES_STOP",
        "bridge": {
            "repository": "besok/graphviz-rust",
            "revisions": {
                "graphviz_and_four_package_surfaces": ROOT_REVISION,
                "dot_structures_0_1_2": DOT_STRUCTURES_REVISION,
            },
            "packages": {
                name: version for name, (version, _) in PACKAGES.items()
            },
            "source_records": records,
            "record_count": len(records),
            "release_tag_resolved": False,
            "crates_io_tarball_checksums_authenticated": False,
            "classification": (
                "PINNED_OFFICIAL_REPOSITORY_MIXED_COMMIT_BUILD_SURFACE"
            ),
        },
        "receipt": receipt,
        "checks": {
            "all_five_manifest_versions_match_lock": True,
            "all_source_records_match_pinned_commit": True,
            "graphviz_stop_cleared": cleared,
            "next_missing_package_authenticated": next_stop,
            "algorithm_compilation_reached": False,
            "algorithm_execution_reached": False,
        },
        "next_build_stop": {
            "class": "MISSING_OFFLINE_REGISTRY_PACKAGE",
            "package": "indicatif",
            "authenticated_by_cargo": True,
        },
        "control_executed": False,
        "source_faithful_controls_reproduced": 3,
        "controls_required": 4,
        "P1_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
        "claim_boundary": (
            "The five graphviz packages match two pinned official repository "
            "commits: the graphviz 0.8.0 surface and the later natural "
            "dot-structures 0.1.2 surface. No release tag or crates.io archive "
            "identity is claimed. Resolution advances to indicatif without "
            "algorithm compilation or execution."
        ),
        "next_action": "audit the exact locked indicatif closure",
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
            and "no matching package named `indicatif` found"
            in frozen_receipt.get("stderr_text", "")
        )
        if current_semantics != frozen_semantics or not valid:
            raise RuntimeError("rerun disagrees with frozen graphviz bridge")
        mode = "VERIFY_FROZEN"
    else:
        RESULT.write_text(canonical(payload) + "\n")
        mode = "CREATE"
    print(
        "FOUNDRY_PHASE120_ISAMORE_GRAPHVIZ_FAMILY"
        " status=ADVANCES_STOP packages=5 records=16 next_stop=indicatif"
        " compiled=false executed=false P1=false"
        f" evidence={mode}"
    )


if __name__ == "__main__":
    main()
