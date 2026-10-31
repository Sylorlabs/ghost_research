#!/usr/bin/env python3
"""Run a pre-frozen alpha-renamed and reordered Stitch control fixture."""

from __future__ import annotations

import json
import os
import pathlib
import subprocess

from phase35_stitch_source_control import (
    CARGO_HOME,
    SOURCE,
    prepare_cargo_home,
    sha256,
    verify_upstream_sources,
)


HERE = pathlib.Path(__file__).resolve().parent
FIXTURE = HERE / "external_controls/stitch/metamorphic_fixture_v1.json"
RESULT = HERE / "results/phase37_stitch_metamorphic_control.json"


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
        raise RuntimeError(f"metamorphic control failed:\n{execution.stderr[-4000:]}")
    observed = json.loads(execution.stdout.strip().splitlines()[-1])
    expected = fixture["expected"]
    abstraction = (
        observed["abstractions"][0] if observed["abstractions"] else None
    )
    checks = {
        "source_records_exact": len(source_rows) == 28,
        "one_abstraction": observed["num_abstractions"]
        == expected["abstractions"],
        "name_exact": abstraction is not None
        and abstraction["name"] == expected["name"],
        "body_invariant": abstraction is not None
        and abstraction["body"] == expected["body"],
        "arity_invariant": abstraction is not None
        and abstraction["arity"] == expected["arity"],
        "renamed_rewrites_exact": observed["rewritten"] == expected["rewritten"],
        "original_cost_invariant": observed["original_cost"]
        == expected["original_cost"],
        "rewritten_cost_invariant": observed["final_cost"]
        == expected["rewritten_cost"],
        "utility_invariant": abstraction is not None
        and abstraction["utility"] == expected["utility"],
        "uses_invariant": abstraction is not None
        and abstraction["num_uses"] == expected["uses"],
    }
    passed = all(checks.values())
    payload = {
        "version": "FOUNDRY_STITCH_METAMORPHIC_CONTROL_V1",
        "status": (
            "STITCH_METAMORPHIC_CONTROL_PASS"
            if passed
            else "STITCH_METAMORPHIC_CONTROL_FAIL"
        ),
        "classification": "PRE_FROZEN_METAMORPHIC_CONTROL",
        "fixture_sha256": sha256(FIXTURE),
        "binary_sha256": sha256(binary),
        "upstream_source_records": len(source_rows),
        "upstream_algorithm_source_executed": True,
        "conformance_executed": True,
        "metamorphic_relation_passed": passed,
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
        "claim_boundary": (
            "This independently frozen metamorphic check rules out a runner "
            "hard-coded only to the published symbols and ordering. It does "
            "not convert the source build into an official wheel execution or "
            "establish control performance on heterogeneous workloads."
        ),
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE37_STITCH_METAMORPHIC"
        f" status={payload['status']}"
        f" relation_passed={str(passed).lower()}"
    )


if __name__ == "__main__":
    run()
