#!/usr/bin/env python3
"""Build and execute pinned upstream Stitch sources against the frozen fixture."""

from __future__ import annotations

import hashlib
import json
import os
import pathlib
import subprocess


HERE = pathlib.Path(__file__).resolve().parent
SOURCE = HERE / "external_controls/stitch/source"
FIXTURE = HERE / "external_controls/stitch/conformance_fixture_v1.json"
RESULT = HERE / "results/phase35_stitch_source_control.json"
CARGO_HOME = pathlib.Path("/tmp/foundry-stitch-cargo-home")

STITCH_GIT_BLOBS = {
    "src/compression.rs": "17c0642c0bc3b5b0292c8271ea60b48d7c55994c",
    "src/egraphs.rs": "162ea525b88b180b8aef014c5232d5243654c1bb",
    "src/expansion.rs": "1438322a43c5fceef4f4b9eda1d5e4f35bd62001",
    "src/formats.rs": "9aea652a283708422d9ff5fb2ce48ac242541b49",
    "src/lib.rs": "0b35523432ba466990779c374a046dc77d9f91d0",
    "src/pattern_args.rs": "2f827294122004c6c63be9c2feea83955d9c0f4d",
    "src/rewriting.rs": "5e240b412e8b8adb9f682aa1990c16928b17dba7",
    "src/symvar.rs": "22a5f390597187af6a885569cd8bdfd87c6971c8",
    "src/tdfa.rs": "0cf22eb2d5cf0c8669de639f959d5d320e807698",
    "src/test_utils.rs": "d189f408ad740dd04905dac0e058286d81649db5",
    "src/util.rs": "4b0c0af8a60f6dd8a177888d9076801d61d12559",
    "src/ziptrie.rs": "3690eb365830ff60aa338866068333697fd6e402",
}

LAMBDAS_GIT_BLOBS = {
    "lambdas/Cargo.toml": "da3c457a857949d55812eebe54f97fef00131207",
    "lambdas/src/analysis.rs": "3fc31c1d21a264e070b2a2b1800099a3a45f787c",
    "lambdas/src/domains/mod.rs": "9f9c938d393ed400ecd2649a10ee46afe272f57d",
    "lambdas/src/domains/prim_lists.rs": "1b60df470f55cb80adc0764a40f61aa440a0901e",
    "lambdas/src/domains/simple.rs": "d650c93f2e8fe8f9a455744c267691cc15a253ba",
    "lambdas/src/dsl.rs": "b78495f1f0be1ac5b25d7a64b29736504fbf07d5",
    "lambdas/src/eval.rs": "ea4449551e83f7371f978619091c42dd3190472c",
    "lambdas/src/expr.rs": "0641ff2f9c17540f04a9b0d061380a015b389722",
    "lambdas/src/lib.rs": "823cc22a350b8a952dbe0169e37620db49a7abac",
    "lambdas/src/macros.rs": "69c1b7fadcdab6926afeb79936198124873a80c4",
    "lambdas/src/parse_expr.rs": "eb6a78fccff634e03a149c309e5c5cf44fb46bcd",
    "lambdas/src/parse_type.rs": "2e89cfbeb550ec39d228543a4856016da5dacfe5",
    "lambdas/src/slow_types.rs": "eb3d05c1ee765ca93bba6300d9cefccbee977fc3",
    "lambdas/src/types.rs": "e4b8e1bb49c5249a39bc064a9ad61773611eef0c",
    "lambdas/src/util.rs": "eb578ab83ce3b6a20116a09b50ad30d7e5f9b9cc",
    "lambdas/src/zipper.rs": "78f4e89394843905e59622d1ae1261782f31bd11",
}


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_blob(path: pathlib.Path) -> str:
    raw = path.read_bytes()
    return hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()


def verify_upstream_sources() -> list[dict[str, str]]:
    rows = []
    for revision, records in (
        ("stitch@0ef5ec7f17091d22b8fa959fb5705e359d735a47", STITCH_GIT_BLOBS),
        ("lambdas@2c9bfd0317974ce82908eaf6d9af530eb4a9019d", LAMBDAS_GIT_BLOBS),
    ):
        for relative, expected in records.items():
            actual = git_blob(SOURCE / relative)
            if actual != expected:
                raise RuntimeError(
                    f"upstream source mismatch: {relative}: {actual} != {expected}"
                )
            rows.append(
                {"path": relative, "git_blob_sha1": actual, "revision": revision}
            )
    return rows


def prepare_cargo_home() -> None:
    registry = CARGO_HOME / "registry"
    registry.mkdir(parents=True, exist_ok=True)
    (registry / "src").mkdir(exist_ok=True)
    upstream = pathlib.Path.home() / ".cargo/registry"
    for name in ("cache", "index"):
        link = registry / name
        if link.is_symlink() and link.resolve() == (upstream / name).resolve():
            continue
        if link.exists() or link.is_symlink():
            raise RuntimeError(f"unexpected cargo-home entry: {link}")
        link.symlink_to(upstream / name, target_is_directory=True)


def run() -> None:
    fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))
    source_rows = verify_upstream_sources()
    prepare_cargo_home()
    env = {
        **os.environ,
        "CARGO_HOME": str(CARGO_HOME),
        "CARGO_NET_OFFLINE": "true",
    }
    cargo = pathlib.Path.home() / ".cargo/bin/cargo"
    build = subprocess.run(
        [
            str(cargo),
            "build",
            "--release",
            "--offline",
            "--quiet",
            "--manifest-path",
            str(SOURCE / "Cargo.toml"),
            "--bin",
            "foundry-stitch-control",
        ],
        cwd=HERE,
        env=env,
        text=True,
        capture_output=True,
        timeout=60,
        check=False,
    )
    if build.returncode != 0:
        raise RuntimeError(f"source build failed:\n{build.stderr[-4000:]}")
    binary = SOURCE / "target/release/foundry-stitch-control"
    execution = subprocess.run(
        [str(binary)],
        cwd=HERE,
        env=env,
        input=json.dumps(fixture["call"]),
        text=True,
        capture_output=True,
        timeout=60,
        check=False,
    )
    if execution.returncode != 0:
        raise RuntimeError(f"source control failed:\n{execution.stderr[-4000:]}")
    observed = json.loads(execution.stdout.strip().splitlines()[-1])
    expected = fixture["expected"]
    abstraction = (
        observed["abstractions"][0] if observed["abstractions"] else None
    )
    checks = {
        "upstream_stitch_blobs_exact": len(STITCH_GIT_BLOBS) == 12,
        "upstream_lambdas_blobs_exact": len(LAMBDAS_GIT_BLOBS) == 16,
        "one_abstraction": observed["num_abstractions"]
        == expected["abstractions"],
        "name_exact": abstraction is not None
        and abstraction["name"] == expected["name"],
        "body_exact": abstraction is not None
        and abstraction["body"] == expected["body"],
        "arity_exact": abstraction is not None
        and abstraction["arity"] == expected["arity"],
        "rewritten_exact": observed["rewritten"] == expected["rewritten"],
        "original_cost_exact": observed["original_cost"]
        == expected["original_cost"],
        "rewritten_cost_exact": observed["final_cost"]
        == expected["rewritten_cost"],
        "utility_exact": abstraction is not None
        and abstraction["utility"] == expected["utility"],
        "uses_exact": abstraction is not None
        and abstraction["num_uses"] == expected["uses"],
    }
    passed = all(checks.values())
    support_paths = (
        "Cargo.toml",
        "Cargo.lock",
        "control_main.rs",
        "clap_derive_shim/Cargo.toml",
        "clap_derive_shim/src/lib.rs",
        "clap_shim/Cargo.toml",
        "clap_shim/src/lib.rs",
        "colorful_shim/Cargo.toml",
        "colorful_shim/src/lib.rs",
        "rustc_hash_1_1_0/.cargo_vcs_info.json",
        "rustc_hash_1_1_0/src/lib.rs",
    )
    payload = {
        "version": "FOUNDRY_STITCH_SOURCE_CONTROL_V1",
        "status": (
            "STITCH_SOURCE_CONTROL_CONFORMANCE_PASS"
            if passed
            else "STITCH_SOURCE_CONTROL_CONFORMANCE_FAIL"
        ),
        "classification": "SOURCE_FAITHFUL_CONTROL_WITH_BUILD_SHIMS",
        "implementation_revision": "0ef5ec7f17091d22b8fa959fb5705e359d735a47",
        "lambdas_revision": "2c9bfd0317974ce82908eaf6d9af530eb4a9019d",
        "fixture_sha256": sha256(FIXTURE),
        "source_records": source_rows,
        "source_records_exact": True,
        "build_support": [
            {"path": path, "sha256": sha256(SOURCE / path)}
            for path in support_paths
        ],
        "binary_sha256": sha256(binary),
        "build_returncode": build.returncode,
        "execution_returncode": execution.returncode,
        "upstream_algorithm_source_executed": True,
        "official_wheel_executed": False,
        "official_binding_executed": False,
        "conformance_executed": True,
        "conformance_passed": passed,
        "checks": checks,
        "observed": {
            "abstractions": observed["num_abstractions"],
            "name": abstraction["name"] if abstraction else None,
            "body": abstraction["body"] if abstraction else None,
            "arity": abstraction["arity"] if abstraction else None,
            "rewritten": observed["rewritten"],
            "original_cost": observed["original_cost"],
            "rewritten_cost": observed["final_cost"],
            "utility": abstraction["utility"] if abstraction else None,
            "uses": abstraction["num_uses"] if abstraction else None,
        },
        "dependency_boundary": {
            "clap": "local defaults-only compatibility shim; no CLI parsing used",
            "colorful": "local display-only no-color compatibility shim",
            "itertools": "0.12.1 substituted for upstream 0.10.x due offline cache",
            "rustc_hash": "exact crates.io 1.1.0 source and version",
            "algorithm_source_files_modified": 0,
        },
        "claim_boundary": (
            "This reproduces the official fixture using byte-exact upstream "
            "Stitch and Lambdas algorithm sources. It is not the official "
            "wheel or Python binding, and dependency/build substitutions mean "
            "it must be reported as a source-faithful control."
        ),
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE35_STITCH_SOURCE"
        f" status={payload['status']}"
        f" source_records={len(source_rows)}"
        f" conformance_passed={str(passed).lower()}"
    )


if __name__ == "__main__":
    run()
