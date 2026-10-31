#!/usr/bin/env python3
"""Build and execute pinned Enumo on its official Boolean simple test."""

from __future__ import annotations

import hashlib
import json
import os
import pathlib
import subprocess

from phase39_enumo_source_closure import GIT_BLOBS


HERE = pathlib.Path(__file__).resolve().parent
ENUMO = HERE / "external_controls/enumo"
CONTROL = ENUMO / "control"
RESULT = HERE / "results/phase45_enumo_source_control.json"
CARGO_HOME = pathlib.Path("/tmp/foundry-enumo-cargo")


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_blob(path: pathlib.Path) -> str:
    data = path.read_bytes()
    return hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()


def prepare_cargo_home() -> None:
    registry = CARGO_HOME / "registry"
    registry.mkdir(parents=True, exist_ok=True)
    (registry / "src").mkdir(exist_ok=True)
    upstream = pathlib.Path.home() / ".cargo/registry"
    for name in ("cache", "index"):
        link = registry / name
        expected = upstream / name
        if link.is_symlink() and link.resolve() == expected.resolve():
            continue
        if link.exists() or link.is_symlink():
            raise RuntimeError(f"unexpected cargo-home entry: {link}")
        link.symlink_to(expected, target_is_directory=True)


def verify_sources() -> list[dict[str, str]]:
    records = []
    for relative, expected in GIT_BLOBS.items():
        actual = git_blob(ENUMO / "source" / relative)
        if actual != expected:
            raise RuntimeError(f"Enumo source mismatch: {relative}")
        records.append(
            {
                "project": "enumo",
                "path": relative,
                "git_blob_sha1": actual,
                "revision": "7ed456de94df26fdddc0c15417a987d101dc57b5",
            }
        )
    manifest = json.loads(
        (ENUMO / "upstream_blobs.json").read_text(encoding="utf-8")
    )
    groups = (
        ("egg", "egg_0_9", "egg_v0_9_5", "v0.9.5"),
        (
            "symbol_table",
            "symbol_table_0_2",
            "symbol_table_v0_2_0",
            "v0.2.0",
        ),
        (
            "ruler_test",
            "upstream_tests",
            "ruler_7ed456_tests",
            "7ed456de94df26fdddc0c15417a987d101dc57b5",
        ),
    )
    for project, directory, key, revision in groups:
        for relative, expected in manifest[key].items():
            actual = git_blob(ENUMO / directory / relative)
            if actual != expected:
                raise RuntimeError(f"{project} source mismatch: {relative}")
            records.append(
                {
                    "project": project,
                    "path": relative,
                    "git_blob_sha1": actual,
                    "revision": revision,
                }
            )
    return records


def run_stage(script: pathlib.Path, env: dict[str, str]) -> str:
    execution = subprocess.run(
        [str(pathlib.Path(os.sys.executable)), str(script)],
        cwd=script.parent,
        env=env,
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )
    if execution.returncode != 0:
        raise RuntimeError(
            f"source stage failed ({script}):\n{execution.stderr[-4000:]}"
        )
    return execution.stdout.strip()


def run() -> None:
    source_records = verify_sources()
    prepare_cargo_home()
    env = {
        **os.environ,
        "CARGO_HOME": str(CARGO_HOME),
        "CARGO_NET_OFFLINE": "true",
    }
    babble_stage = run_stage(
        HERE / "external_controls/babble/control/prepare_source.py", env
    )
    egg_stage = run_stage(ENUMO / "egg_control/prepare_source.py", env)
    enumo_stage = run_stage(CONTROL / "prepare_source.py", env)
    if (
        "exact_blobs=62/62" not in babble_stage
        or "exact_modules=16/16" not in egg_stage
        or "exact_modules=12/12" not in enumo_stage
    ):
        raise RuntimeError("dependency source-integrity stage was incomplete")

    cargo = pathlib.Path.home() / ".cargo/bin/cargo"
    build = subprocess.run(
        [
            str(cargo),
            "build",
            "--release",
            "--offline",
            "--quiet",
            "--manifest-path",
            str(CONTROL / "Cargo.toml"),
        ],
        cwd=CONTROL,
        env=env,
        text=True,
        capture_output=True,
        timeout=120,
        check=False,
    )
    if build.returncode != 0:
        raise RuntimeError(f"Enumo source build failed:\n{build.stderr[-4000:]}")
    binary = CONTROL / "target/release/foundry-enumo-control"
    execution = subprocess.run(
        [str(binary)],
        cwd=CONTROL,
        env=env,
        text=True,
        capture_output=True,
        timeout=120,
        check=False,
    )
    if execution.returncode != 0:
        raise RuntimeError(
            f"Enumo Boolean control failed:\n{execution.stderr[-4000:]}"
        )
    observed = json.loads(execution.stdout.strip().splitlines()[-1])
    checks = {
        "direct_upstream_git_blobs_exact": len(source_records) == 49,
        "dependency_integrity_stage_complete": True,
        "official_workload_counts_exact": observed["workload_counts"]
        == [93, 348, 4599],
        "all_official_expected_rules_derivable": observed[
            "derivable_expected"
        ]
        == observed["expected_rules"]
        == 43,
        "zero_official_expected_rules_missing": observed[
            "nonderivable_expected"
        ]
        == 0,
        "nonempty_learned_ruleset": observed["total_rules"] > 0,
    }
    passed = all(checks.values())
    support_paths = (
        "control/Cargo.toml",
        "control/Cargo.lock",
        "control/prepare_source.py",
        "control/src/main.rs",
        "egg_control/Cargo.toml",
        "egg_control/prepare_source.py",
        "symbol_table_control/Cargo.toml",
        "upstream_blobs.json",
    )
    payload = {
        "version": "FOUNDRY_ENUMO_SOURCE_CONTROL_V1",
        "status": (
            "ENUMO_SOURCE_CONTROL_CONFORMANCE_PASS"
            if passed
            else "ENUMO_SOURCE_CONTROL_CONFORMANCE_FAIL"
        ),
        "classification": "SOURCE_FAITHFUL_CORE_CONTROL_WITH_BUILD_ADAPTATION",
        "enumo_revision": "7ed456de94df26fdddc0c15417a987d101dc57b5",
        "egg_release": "v0.9.5",
        "symbol_table_release": "v0.2.0",
        "source_records": source_records,
        "source_records_exact": True,
        "upstream_algorithm_source_executed": True,
        "official_boolean_test_logic_executed": True,
        "full_official_crate_executed": False,
        "conformance_executed": True,
        "conformance_passed": passed,
        "checks": checks,
        "observed": observed,
        "binary_sha256": sha256(binary),
        "build_support": [
            {"path": path, "sha256": sha256(ENUMO / path)}
            for path in support_paths
        ],
        "dependency_boundary": {
            "enumo_core": "12 byte-exact rule/workload/language modules",
            "enumo_excluded": "BV/Z3 domain, logger, and CLI-only dependencies",
            "egg": (
                "16 byte-exact Egg 0.9.5 core modules; generated build excludes "
                "test/docs and selects Egg's declared FxBuildHasher"
            ),
            "symbol_table": (
                "byte-exact v0.2.0 source with Ahash 0.8 substituted for 0.7"
            ),
            "itertools": "0.12.1 substituted for Enumo 0.9.x",
            "official_domain": "byte-exact tests/bool.rs",
            "official_expected_set": (
                "the exact tests/bool.rs simple-test list, 43 directed rules "
                "after bidirectional expansion"
            ),
        },
        "claim_boundary": (
            "This executes Enumo's pinned rule-inference/minimization core, "
            "Egg 0.9.5, its exact Boolean domain, and the published simple-test "
            "logic. It excludes the independent BV/Z3 and logging surfaces and "
            "is therefore a source-faithful core control, not a full official "
            "crate build."
        ),
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE45_ENUMO_SOURCE"
        f" status={payload['status']}"
        f" source_records={len(source_records)}"
        f" workloads={observed['workload_counts']}"
        f" derives={observed['derivable_expected']}/"
        f"{observed['expected_rules']}"
    )


if __name__ == "__main__":
    run()
