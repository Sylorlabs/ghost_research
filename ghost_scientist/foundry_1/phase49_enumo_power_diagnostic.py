#!/usr/bin/env python3
"""Post-hoc diagnostic of Enumo rule-set proving-power equivalence."""

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
DIAGNOSTIC = ENUMO / "diagnostic_control"
BASELINE = HERE / "results/phase45_enumo_source_control.json"
TRANSFORMED = HERE / "results/phase47_enumo_metamorphic_control.json"
RESULT = HERE / "results/phase49_enumo_power_diagnostic.json"


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
    cargo = pathlib.Path.home() / ".cargo/bin/cargo"
    build = subprocess.run(
        [
            str(cargo),
            "build",
            "--release",
            "--offline",
            "--quiet",
            "--manifest-path",
            str(DIAGNOSTIC / "Cargo.toml"),
        ],
        cwd=DIAGNOSTIC,
        env=env,
        text=True,
        capture_output=True,
        timeout=120,
        check=False,
    )
    if build.returncode != 0:
        raise RuntimeError(
            f"Enumo diagnostic build failed:\n{build.stderr[-4000:]}"
        )
    binary = DIAGNOSTIC / "target/release/foundry-enumo-power-diagnostic"
    execution = subprocess.run(
        [str(binary), str(BASELINE), str(TRANSFORMED)],
        cwd=DIAGNOSTIC,
        env=env,
        text=True,
        capture_output=True,
        timeout=120,
        check=False,
    )
    if execution.returncode != 0:
        raise RuntimeError(
            f"Enumo power diagnostic failed:\n{execution.stderr[-4000:]}"
        )
    observed = json.loads(execution.stdout.strip().splitlines()[-1])
    baseline_covers_transformed = (
        not observed["baseline_misses_transformed"]
        and observed["baseline_derives_transformed"]
        == observed["transformed_rules"]
    )
    transformed_covers_baseline = (
        not observed["transformed_misses_baseline"]
        and observed["transformed_derives_baseline"]
        == observed["baseline_rules"]
    )
    payload = {
        "version": "FOUNDRY_ENUMO_POWER_DIAGNOSTIC_V1",
        "status": (
            "ENUMO_BOUNDED_PROVING_POWER_EQUIVALENT"
            if baseline_covers_transformed and transformed_covers_baseline
            else "ENUMO_BOUNDED_PROVING_POWER_DIVERGED"
        ),
        "classification": "POST_HOC_AFTER_METAMORPHIC_FAILURE",
        "source_records_exact": len(source_records) == 49,
        "baseline_result_sha256": sha256(BASELINE),
        "transformed_result_sha256": sha256(TRANSFORMED),
        "baseline_derives_entire_transformed_set": baseline_covers_transformed,
        "transformed_derives_entire_baseline_set": transformed_covers_baseline,
        "observed": observed,
        "claim_boundary": (
            "This diagnostic was designed after the frozen syntactic-set "
            "failure. It can characterize bounded mutual derivability but "
            "cannot retroactively turn that failed pre-frozen criterion into "
            "a pass or prove unbounded logical equivalence."
        ),
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE49_ENUMO_POWER"
        f" status={payload['status']}"
        f" baseline_to_transformed="
        f"{observed['baseline_derives_transformed']}/"
        f"{observed['transformed_rules']}"
        f" transformed_to_baseline="
        f"{observed['transformed_derives_baseline']}/"
        f"{observed['baseline_rules']}"
    )


if __name__ == "__main__":
    run()
