#!/usr/bin/env python3
"""Build and execute the pinned Babble POPL23 core on its README example."""

from __future__ import annotations

import hashlib
import json
import os
import pathlib
import re
import subprocess


HERE = pathlib.Path(__file__).resolve().parent
CONTROL = HERE / "external_controls/babble/control"
FIXTURE = CONTROL / "fixtures/readme_simple.bab"
RESULT = HERE / "results/phase41_babble_source_control.json"
CARGO_HOME = pathlib.Path("/tmp/foundry-babble-cargo")

EXPECTED_LEARNED = (
    '("lib LIB" (λ (cons $0 (cons $0 (cons $0 empty)))) (@ LIB ?x0))'
)
EXPECTED_REWRITTEN = """\
lib LIB =
  λx1 -> x1 : x1 : x1 : []
in
  [LIB 0,
    LIB 1,
    LIB 2,
    LIB 3]"""


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def normalize_lib_ids(value: str) -> str:
    return re.sub(r"\bl\d+\b", "LIB", value)


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


def run() -> None:
    prepare_cargo_home()
    env = {
        **os.environ,
        "CARGO_HOME": str(CARGO_HOME),
        "CARGO_NET_OFFLINE": "true",
    }
    stage = subprocess.run(
        [str(pathlib.Path(os.sys.executable)), str(CONTROL / "prepare_source.py")],
        cwd=CONTROL,
        env=env,
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )
    if stage.returncode != 0:
        raise RuntimeError(f"source stage failed:\n{stage.stderr[-4000:]}")
    source_manifest = json.loads(
        (CONTROL / "generated/source_manifest.json").read_text(encoding="utf-8")
    )
    exact_blobs = (
        len(source_manifest["verified_babble_git_blobs"])
        + len(source_manifest["verified_dependency_git_blobs"])
    )

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
        timeout=90,
        check=False,
    )
    if build.returncode != 0:
        raise RuntimeError(f"source build failed:\n{build.stderr[-4000:]}")

    binary = CONTROL / "target/release/foundry-babble-control"
    execution = subprocess.run(
        [str(binary), str(FIXTURE)],
        cwd=CONTROL,
        env=env,
        text=True,
        capture_output=True,
        timeout=60,
        check=False,
    )
    if execution.returncode != 0:
        raise RuntimeError(f"source control failed:\n{execution.stderr[-4000:]}")
    observed = json.loads(execution.stdout.strip().splitlines()[-1])
    learned = [normalize_lib_ids(value) for value in observed["learned_bodies"]]
    rewritten = normalize_lib_ids(observed["rewritten"])
    checks = {
        "pinned_source_closure_exact": exact_blobs == 62,
        "single_algorithm_neutral_rustc_patch": len(
            source_manifest["generated_compatibility_patches"]
        )
        == 1,
        "readme_input_cost_exact": observed["initial_cost"] == 29,
        "one_library_selected": observed["chosen_libraries"] == 1,
        "learned_structure_exact_after_id_normalization": learned
        == [EXPECTED_LEARNED],
        "rewritten_structure_exact_after_id_normalization": rewritten
        == EXPECTED_REWRITTEN,
        "strict_cost_improvement": observed["final_cost"]
        < observed["initial_cost"],
        "source_ast_cost_recomputed": observed["final_cost"] == 22,
    }
    passed = all(checks.values())
    support_paths = (
        "Cargo.toml",
        "Cargo.lock",
        "prepare_source.py",
        "src/main.rs",
        "fixtures/readme_simple.bab",
        "../egg_control/Cargo.toml",
    )
    payload = {
        "version": "FOUNDRY_BABBLE_SOURCE_CONTROL_V1",
        "status": (
            "BABBLE_SOURCE_CONTROL_STRUCTURAL_PASS"
            if passed
            else "BABBLE_SOURCE_CONTROL_STRUCTURAL_FAIL"
        ),
        "classification": "SOURCE_FAITHFUL_CORE_CONTROL_WITH_BUILD_ADAPTATION",
        "babble_revision": source_manifest["commit"],
        "egg_revision": source_manifest["egg_commit"],
        "source_records_exact": True,
        "source_records": exact_blobs,
        "upstream_algorithm_source_executed": True,
        "full_official_cli_executed": False,
        "conformance_executed": True,
        "structural_conformance_passed": passed,
        "checks": checks,
        "fixture_sha256": sha256(FIXTURE),
        "binary_sha256": sha256(binary),
        "build_support": [
            {"path": path, "sha256": sha256(CONTROL / path)}
            for path in support_paths
        ],
        "observed": {
            **observed,
            "learned_bodies_normalized": learned,
            "rewritten_normalized": rewritten,
        },
        "published_claim_audit": {
            "readme_initial_cost": 29,
            "readme_final_cost": 23,
            "source_observed_initial_cost": observed["initial_cost"],
            "source_observed_final_cost": observed["final_cost"],
            "numeric_claim_exact": observed["final_cost"] == 23,
            "structure_claim_exact_after_id_normalization": passed,
            "interpretation": (
                "The pinned source constructs the published library shape but "
                "AstSize counts that displayed result as 22, not README's 23."
            ),
        },
        "dependency_boundary": {
            "babble_core": "byte-exact staged modules from pinned POPL23 commit",
            "egg_core": "byte-exact source from Babble lockfile commit",
            "rustc_compatibility": (
                "one generated Self(node) to Expr(node) qualification; pinned "
                "source remains unchanged"
            ),
            "itertools": "0.12.1 substituted for upstream 0.10.x offline",
            "hashbrown": "0.12.3 substituted for Egg 0.11.x offline",
            "excluded": "Babble experiment CSV/CLI, DreamCoder, and Gurobi surfaces",
        },
        "claim_boundary": (
            "This executes the pinned Babble and Egg learning/extraction core "
            "with a deterministic build adaptation. It is not the complete "
            "official artifact CLI. Structural behavior passes; the README's "
            "published final-cost number does not match the pinned source's "
            "AstSize result and is preserved as a discrepancy."
        ),
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE41_BABBLE_SOURCE"
        f" status={payload['status']}"
        f" source_records={exact_blobs}"
        f" structural_pass={str(passed).lower()}"
        f" readme_cost_exact="
        f"{str(payload['published_claim_audit']['numeric_claim_exact']).lower()}"
    )


if __name__ == "__main__":
    run()
