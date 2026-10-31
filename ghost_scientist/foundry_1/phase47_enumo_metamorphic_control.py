#!/usr/bin/env python3
"""Run the pre-frozen renamed/reordered Enumo Boolean workload."""

from __future__ import annotations

import json
import os
import pathlib
import subprocess

from phase45_enumo_source_control import (
    CARGO_HOME,
    CONTROL,
    ENUMO,
    prepare_cargo_home,
    run_stage,
    sha256,
    verify_sources,
)


HERE = pathlib.Path(__file__).resolve().parent
METAMORPHIC = ENUMO / "metamorphic_control"
RESULT = HERE / "results/phase47_enumo_metamorphic_control.json"
BASELINE = HERE / "results/phase45_enumo_source_control.json"


def run() -> None:
    source_records = verify_sources()
    prepare_cargo_home()
    env = {
        **os.environ,
        "CARGO_HOME": str(CARGO_HOME),
        "CARGO_NET_OFFLINE": "true",
    }
    run_stage(HERE / "external_controls/babble/control/prepare_source.py", env)
    run_stage(ENUMO / "egg_control/prepare_source.py", env)
    run_stage(CONTROL / "prepare_source.py", env)
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))["observed"]

    cargo = pathlib.Path.home() / ".cargo/bin/cargo"
    build = subprocess.run(
        [
            str(cargo),
            "build",
            "--release",
            "--offline",
            "--quiet",
            "--manifest-path",
            str(METAMORPHIC / "Cargo.toml"),
        ],
        cwd=METAMORPHIC,
        env=env,
        text=True,
        capture_output=True,
        timeout=120,
        check=False,
    )
    if build.returncode != 0:
        raise RuntimeError(
            f"Enumo metamorphic build failed:\n{build.stderr[-4000:]}"
        )
    binary = METAMORPHIC / "target/release/foundry-enumo-metamorphic"
    execution = subprocess.run(
        [str(binary)],
        cwd=METAMORPHIC,
        env=env,
        text=True,
        capture_output=True,
        timeout=120,
        check=False,
    )
    if execution.returncode != 0:
        raise RuntimeError(
            f"Enumo metamorphic run failed:\n{execution.stderr[-4000:]}"
        )
    observed = json.loads(execution.stdout.strip().splitlines()[-1])
    checks = {
        "direct_upstream_git_blobs_exact": len(source_records) == 49,
        "workload_counts_invariant": observed["workload_counts"]
        == baseline["workload_counts"],
        "stage_rule_counts_invariant": observed["stage_rule_counts"]
        == baseline["stage_rule_counts"],
        "total_rule_count_invariant": observed["total_rules"]
        == baseline["total_rules"],
        "entire_sorted_rule_set_invariant": observed["learned_rules"]
        == baseline["learned_rules"],
    }
    passed = all(checks.values())
    payload = {
        "version": "FOUNDRY_ENUMO_METAMORPHIC_CONTROL_V1",
        "status": (
            "ENUMO_METAMORPHIC_CONTROL_PASS"
            if passed
            else "ENUMO_METAMORPHIC_CONTROL_FAIL"
        ),
        "classification": "PRE_FROZEN_METAMORPHIC_SOURCE_CONTROL",
        "source_records": len(source_records),
        "baseline_result_sha256": sha256(BASELINE),
        "binary_sha256": sha256(binary),
        "upstream_algorithm_source_executed": True,
        "metamorphic_relation_passed": passed,
        "checks": checks,
        "observed": observed,
        "claim_boundary": (
            "This pre-frozen transformation changes literal variable names "
            "and enumeration order and compares the entire learned directed "
            "rule set. It remains the same Enumo Boolean domain and does not "
            "count as a fourth independent control."
        ),
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE47_ENUMO_METAMORPHIC"
        f" status={payload['status']}"
        f" relation_passed={str(passed).lower()}"
        f" rules={observed['total_rules']}"
    )


if __name__ == "__main__":
    run()
