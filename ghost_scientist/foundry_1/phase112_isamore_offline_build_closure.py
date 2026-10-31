#!/usr/bin/env python3
"""Run a metered, offline ISAMORE build-closure audit."""

from __future__ import annotations

import ctypes.util
import json
import pathlib
import shutil

from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SOURCE = HERE / "external_controls/isamore/source"
ACQUISITION = (
    HERE / "results/phase111_isamore_recursive_source_acquisition.json"
)
RESULT = HERE / "results/phase112_isamore_offline_build_closure.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def cargo_receipt(args: list[str], wall: int) -> dict:
    cargo = shutil.which("cargo")
    if cargo is None:
        raise RuntimeError("cargo is unavailable")
    return run_metered_tree(
        [str(pathlib.Path(cargo).absolute()), *args],
        cwd=SOURCE,
        wall_limit_seconds=wall,
        cpu_limit_seconds=max(10, wall - 5),
        rss_limit_kib=2_000_000,
        environment={
            "RUSTUP_TOOLCHAIN": "stable",
            "CARGO_NET_OFFLINE": "true",
            "CARGO_TERM_COLOR": "never",
            "RUST_BACKTRACE": "0",
        },
    )


def main() -> None:
    acquisition = json.loads(ACQUISITION.read_text())
    if (
        acquisition["status"]
        != "ISAMORE_SOURCE_ACQUISITION_COMPONENT_PASS"
        or acquisition["control_executed"] is not False
    ):
        raise RuntimeError("ISAMORE source acquisition is not valid")

    metadata = cargo_receipt(
        ["metadata", "--locked", "--no-deps", "--format-version", "1"], 30
    )
    check = cargo_receipt(["check", "--locked", "--lib"], 90)
    missing_colored = (
        "no matching package named `colored` found" in check["stderr_text"]
    )
    metadata_ok = (
        metadata["returncode"] == 0
        and metadata["termination"] == "natural"
        and '"name":"isamore"' in metadata["stdout_text"]
    )
    expected_infrastructure_stop = (
        check["returncode"] != 0
        and check["termination"] == "natural"
        and missing_colored
    )
    if not metadata_ok or not expected_infrastructure_stop:
        raise RuntimeError(
            "unexpected ISAMORE offline build audit behavior: "
            + canonical(
                {
                    "metadata_returncode": metadata["returncode"],
                    "check_returncode": check["returncode"],
                    "check_stderr": check["stderr_text"][-1000:],
                }
            )
        )

    nightly = (
        pathlib.Path.home()
        / ".rustup/toolchains/nightly-2024-12-25-x86_64-unknown-linux-gnu"
    )
    native = {
        "protoc_present": shutil.which("protoc") is not None,
        "system_libz3_present": ctypes.util.find_library("z3") is not None,
        "system_coin_cbc_present": (
            ctypes.util.find_library("Cbc") is not None
        ),
        "pinned_nightly_present": nightly.is_dir(),
        "jlm_opt_present": shutil.which("jlm-opt") is not None,
    }
    defining_surfaces = {
        "anti_unification_source_present": (
            SOURCE / "babble/src/au_merge.rs"
        ).is_file(),
        "smt_validation_source_present": (
            SOURCE / "src/egg_lang/synth_enumo.rs"
        ).is_file(),
        "lp_extraction_source_present": (
            SOURCE / "egg/src/lp_extract.rs"
        ).is_file(),
        "hardware_cost_source_present": (
            SOURCE / "src/egg_lang/schedule.rs"
        ).is_file(),
        "published_workload_present": acquisition["published_workload"][
            "present"
        ],
    }
    route_buildable = (
        check["returncode"] == 0
        and all(defining_surfaces.values())
        and native["system_coin_cbc_present"]
        and native["pinned_nightly_present"]
    )
    if route_buildable:
        raise RuntimeError("unexpected ISAMORE route-buildable classification")

    payload = {
        "version": "FOUNDRY_ISAMORE_OFFLINE_BUILD_CLOSURE_V1",
        "status": "ISAMORE_BUILD_CLOSURE_AUTHENTICATED_STOP",
        "source_acquisition_status": acquisition["status"],
        "metadata_receipt": metadata,
        "build_receipt": check,
        "checks": {
            "offline_locked_metadata_resolved": metadata_ok,
            "offline_locked_build_attempted": True,
            "first_missing_registry_package_authenticated": missing_colored,
            "failure_is_infrastructure_not_control_outcome": True,
            "all_defining_source_surfaces_present": all(
                defining_surfaces.values()
            ),
            "route_buildable": route_buildable,
        },
        "defining_surfaces": defining_surfaces,
        "native_closure": native,
        "first_build_stop": {
            "class": "MISSING_OFFLINE_REGISTRY_PACKAGE",
            "package": "colored",
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
            "Cargo resolves the exact local workspace and authenticated lock "
            "offline, then stops before compilation because the first locked "
            "registry package is absent. No ISAMORE algorithm or outcome ran. "
            "The missing pinned nightly and Coin-OR CBC runtime independently "
            "prevent the defining LP path from being claimed executable."
        ),
        "next_action": (
            "acquire the exact locked registry closure and Coin-OR CBC plus "
            "the pinned nightly, then rerun the unchanged metered build audit; "
            "do not replace SMT or LP selection with a mock and do not count "
            "source acquisition as P1"
        ),
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE112_ISAMORE_BUILD_CLOSURE"
        f" status={payload['status']}"
        " metadata=PASS build=INFRASTRUCTURE_STOP"
        " package=colored controls=3/4 P1=false prospective=false"
    )


if __name__ == "__main__":
    main()
