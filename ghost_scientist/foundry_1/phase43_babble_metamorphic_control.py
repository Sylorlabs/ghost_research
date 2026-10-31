#!/usr/bin/env python3
"""Run the pre-frozen value-renamed and reordered Babble control fixture."""

from __future__ import annotations

import json
import os
import pathlib
import subprocess

from phase41_babble_source_control import (
    CARGO_HOME,
    CONTROL,
    EXPECTED_LEARNED,
    normalize_lib_ids,
    prepare_cargo_home,
    sha256,
)


HERE = pathlib.Path(__file__).resolve().parent
FIXTURE = CONTROL / "fixtures/metamorphic_v1.bab"
RESULT = HERE / "results/phase43_babble_metamorphic_control.json"
EXPECTED_REWRITTEN = """\
lib LIB =
  λx1 -> x1 : x1 : x1 : []
in
  [LIB 42,
    LIB -3,
    LIB 11,
    LIB 7]"""


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
    source_records = (
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
        raise RuntimeError(f"metamorphic control failed:\n{execution.stderr[-4000:]}")
    observed = json.loads(execution.stdout.strip().splitlines()[-1])
    learned = [
        normalize_lib_ids(value) for value in observed["learned_bodies"]
    ]
    rewritten = normalize_lib_ids(observed["rewritten"])
    checks = {
        "source_records_exact": source_records == 62,
        "initial_cost_invariant": observed["initial_cost"] == 29,
        "final_cost_invariant": observed["final_cost"] == 22,
        "candidate_count_invariant": observed["candidate_patterns"] == 7,
        "one_library_selected": observed["chosen_libraries"] == 1,
        "learned_shape_invariant": learned == [EXPECTED_LEARNED],
        "renamed_reordered_output_exact": rewritten == EXPECTED_REWRITTEN,
    }
    passed = all(checks.values())
    payload = {
        "version": "FOUNDRY_BABBLE_METAMORPHIC_CONTROL_V1",
        "status": (
            "BABBLE_METAMORPHIC_CONTROL_PASS"
            if passed
            else "BABBLE_METAMORPHIC_CONTROL_FAIL"
        ),
        "classification": "PRE_FROZEN_METAMORPHIC_SOURCE_CONTROL",
        "fixture_sha256": sha256(FIXTURE),
        "binary_sha256": sha256(binary),
        "source_records": source_records,
        "upstream_algorithm_source_executed": True,
        "metamorphic_relation_passed": passed,
        "checks": checks,
        "observed": {
            **observed,
            "learned_bodies_normalized": learned,
            "rewritten_normalized": rewritten,
        },
        "claim_boundary": (
            "This pre-frozen transformation rules out dependence on the "
            "README's literal constants and ordering. It retains the repeated-"
            "triple motif and therefore is not heterogeneous task evidence."
        ),
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE43_BABBLE_METAMORPHIC"
        f" status={payload['status']}"
        f" relation_passed={str(passed).lower()}"
    )


if __name__ == "__main__":
    run()
