#!/usr/bin/env python3
"""Advance the ISAMORE offline build with an authenticated auxiliary crate."""

from __future__ import annotations

import hashlib
import json
import pathlib
import shutil
import tomllib

from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
SOURCE = HERE / "external_controls/isamore/source"
VENDOR = HERE / "external_controls/isamore/vendor/colored-3.1.1"
PRIOR = HERE / "results/phase112_isamore_offline_build_closure.json"
RESULT = HERE / "results/phase113_isamore_colored_bridge_audit.json"
EXPECTED = {
    "Cargo.toml": "6a0832c59dc7e5d4ae5b8b0f78151055d9c1a659",
    "LICENSE": "14e2f777f6c395e7e04ab4aa306bbcc4b0c1120e",
    "README.md": "c0ee7f9a7814cf4fde302964d3c43bf4a8dd0f75",
    "src/lib.rs": "fe8f3e36a45ad2d7754cf5daeddaef0a71596d03",
    "src/color.rs": "ff4767da5a3504686990874630612e896d51bdaa",
    "src/control.rs": "2d6081547938380e032abac48b3e786662cea478",
    "src/error.rs": "06c5d492d8013c3560405b25133b375e1889aa48",
    "src/style.rs": "9ab2b94cdf8ef45ff240905499212afe70855eba",
    "src/customcolors.rs": "fcf6982b2307ec19f81f95bf51e6b8412eaa4217",
}


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def git_blob(path: pathlib.Path) -> str:
    raw = path.read_bytes()
    return hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior = json.loads(PRIOR.read_text())
    if not (
        prior["status"] == "ISAMORE_BUILD_CLOSURE_AUTHENTICATED_STOP"
        and prior["first_build_stop"]["package"] == "colored"
        and prior["control_executed"] is False
    ):
        raise RuntimeError("prior ISAMORE build stop changed")

    records = []
    for relative, expected in EXPECTED.items():
        path = VENDOR / relative
        actual = git_blob(path)
        if actual != expected:
            raise RuntimeError(
                f"colored tag source mismatch: {relative}: "
                f"{actual} != {expected}"
            )
        records.append(
            {
                "path": str(path.relative_to(HERE)),
                "git_blob_sha1": actual,
                "sha256": sha256(path),
                "bytes": path.stat().st_size,
            }
        )
    manifest = tomllib.loads((VENDOR / "Cargo.toml").read_text())
    if manifest["package"]["name"] != "colored" or (
        manifest["package"]["version"] != "3.1.1"
    ):
        raise RuntimeError("colored bridge manifest identity changed")

    cargo = shutil.which("cargo")
    if cargo is None:
        raise RuntimeError("cargo unavailable")
    receipt = run_metered_tree(
        [
            str(pathlib.Path(cargo).absolute()),
            "--config",
            'patch.crates-io.colored.path="../vendor/colored-3.1.1"',
            "check",
            "--locked",
            "--lib",
        ],
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
        and "no matching package named `crossbeam` found"
        in receipt["stderr_text"]
    )
    colored_stop_cleared = (
        "no matching package named `colored` found"
        not in receipt["stderr_text"]
    )
    if not next_stop or not colored_stop_cleared:
        raise RuntimeError(
            "colored bridge did not advance the expected build stop: "
            + receipt["stderr_text"]
        )
    payload = {
        "version": "FOUNDRY_ISAMORE_COLORED_BRIDGE_AUDIT_V1",
        "status": "ISAMORE_AUXILIARY_DEPENDENCY_BRIDGE_ADVANCES_STOP",
        "bridge": {
            "package": "colored",
            "version": "3.1.1",
            "repository": "colored-rs/colored",
            "tag": "v3.1.1",
            "role": "logging_and_terminal_formatting_only",
            "source_records": records,
            "source_records_exact_to_official_tag": True,
            "crates_io_tarball_checksum_authenticated": False,
            "classification": "OFFICIAL_TAG_BUILD_BRIDGE",
        },
        "receipt": receipt,
        "checks": {
            "prior_colored_stop_authenticated": True,
            "official_tag_source_exact": True,
            "locked_package_version_matches": True,
            "colored_stop_cleared": colored_stop_cleared,
            "next_missing_package_authenticated": next_stop,
            "algorithm_compilation_reached": False,
            "algorithm_execution_reached": False,
        },
        "next_build_stop": {
            "class": "MISSING_OFFLINE_REGISTRY_PACKAGE",
            "package": "crossbeam",
            "authenticated_by_cargo": True,
        },
        "control_executed": False,
        "conformance_executed": False,
        "source_faithful_controls_reproduced": 3,
        "controls_required": 4,
        "P1_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
        "claim_boundary": (
            "An official-tag source bridge for the auxiliary colored 3.1.1 "
            "package advances the offline build stop from colored to "
            "crossbeam. It is not the crates.io tarball checksum, no ISAMORE "
            "algorithm compiled or ran, and it does not close the locked "
            "dependency chain."
        ),
        "next_action": (
            "authenticate the locked crossbeam 0.8.4 source closure and rerun "
            "the same metered command; preserve every source substitution in "
            "the evidence chain and abandon the bridge if it reaches a "
            "defining semantic dependency that cannot be exact"
        ),
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE113_ISAMORE_COLORED_BRIDGE"
        f" status={payload['status']}"
        " colored=OFFICIAL_TAG next_stop=crossbeam"
        " compiled=false executed=false controls=3/4 P1=false"
    )


if __name__ == "__main__":
    main()
