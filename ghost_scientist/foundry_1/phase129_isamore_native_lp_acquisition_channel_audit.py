#!/usr/bin/env python3
"""Audit user-local native CBC and pinned-nightly acquisition channels."""

from __future__ import annotations

import ctypes.util
import json
import pathlib
import shutil
import subprocess
import tempfile


HERE = pathlib.Path(__file__).resolve().parent
PRIOR = HERE / "results/phase128_isamore_coin_cbc_binding_bridge_audit.json"
RESULT = HERE / "results/phase129_isamore_native_lp_acquisition_channel_audit.json"
APT_VERSION = "2.10.11+ds1-2"
TOOLCHAIN = "nightly-2024-12-25-x86_64-unknown-linux-gnu"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def native_state() -> dict:
    toolchain = pathlib.Path.home() / ".rustup/toolchains" / TOOLCHAIN
    rustup_downloads = pathlib.Path.home() / ".rustup/downloads"
    cached_toolchain_files = (
        sorted(str(path) for path in rustup_downloads.rglob("*") if path.is_file())
        if rustup_downloads.is_dir()
        else []
    )
    apt_archives = pathlib.Path("/var/cache/apt/archives")
    cached_debs = (
        sorted(
            str(path)
            for path in apt_archives.glob("coinor-*cbc*.deb")
            if path.is_file()
        )
        if apt_archives.is_dir()
        else []
    )
    return {
        "system_libcbc_present": ctypes.util.find_library("Cbc") is not None,
        "cbc_executable_present": shutil.which("cbc") is not None,
        "pinned_nightly_present": toolchain.is_dir(),
        "cached_coin_cbc_debs": cached_debs,
        "rustup_download_cache_files": cached_toolchain_files,
    }


def apt_policy(package: str) -> dict:
    apt_cache = shutil.which("apt-cache")
    if apt_cache is None:
        raise RuntimeError("apt-cache unavailable")
    completed = subprocess.run(
        [apt_cache, "policy", package],
        text=True,
        capture_output=True,
        timeout=10,
        check=False,
    )
    return {
        "package": package,
        "returncode": completed.returncode,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
    }


def acquisition_probe() -> dict:
    apt_get = shutil.which("apt-get")
    if apt_get is None:
        raise RuntimeError("apt-get unavailable")
    with tempfile.TemporaryDirectory(prefix="foundry-cbc-acquire-") as tmp:
        completed = subprocess.run(
            [
                apt_get,
                "download",
                "coinor-libcbc-dev",
                "coinor-cbc",
            ],
            cwd=tmp,
            text=True,
            capture_output=True,
            timeout=30,
            check=False,
        )
        artifacts = sorted(
            {
                "name": path.name,
                "bytes": path.stat().st_size,
            }
            for path in pathlib.Path(tmp).iterdir()
            if path.is_file()
        )
    return {
        "argv": [
            apt_get,
            "download",
            "coinor-libcbc-dev",
            "coinor-cbc",
        ],
        "returncode": completed.returncode,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
        "downloaded_artifacts": artifacts,
        "system_install_attempted": False,
    }


def validate_absence() -> dict:
    state = native_state()
    if (
        state["system_libcbc_present"]
        or state["cbc_executable_present"]
        or state["pinned_nightly_present"]
        or state["cached_coin_cbc_debs"]
    ):
        raise RuntimeError("native LP closure changed; advance this phase")
    return state


def create() -> dict:
    prior = json.loads(PRIOR.read_text())
    if not (
        prior["status"]
        == "ISAMORE_COIN_CBC_RUST_BINDINGS_COMPILE_NATIVE_UNAVAILABLE"
        and prior["checks"]["rust_binding_source_compilation_passed"] is True
        and prior["checks"]["native_libcbc_available"] is False
        and prior["checks"]["pinned_nightly_available"] is False
        and prior["next_build_stop"]["package"] == "kiddo"
    ):
        raise RuntimeError("prior Coin-CBC binding boundary changed")
    state = validate_absence()
    policies = [
        apt_policy("coinor-libcbc-dev"),
        apt_policy("coinor-cbc"),
    ]
    for policy in policies:
        if (
            policy["returncode"] != 0
            or f"Candidate: {APT_VERSION}" not in policy["stdout"]
        ):
            raise RuntimeError("expected CBC apt candidate changed")
    probe = acquisition_probe()
    combined = probe["stdout"] + probe["stderr"]
    if not (
        probe["returncode"] != 0
        and "Could not resolve 'apt.pop-os.org'" in combined
        and probe["downloaded_artifacts"] == []
    ):
        raise RuntimeError("native CBC acquisition probe changed")
    return {
        "version": "FOUNDRY_ISAMORE_NATIVE_LP_ACQUISITION_CHANNEL_AUDIT_V1",
        "status": "ISAMORE_NATIVE_LP_CHANNELS_IDENTIFIED_TRANSPORT_UNAVAILABLE",
        "native_state": state,
        "apt_channels": {
            "candidate_version": APT_VERSION,
            "packages": ["coinor-libcbc-dev", "coinor-cbc"],
            "policy_receipts": policies,
            "download_probe": probe,
            "download_only_no_system_install": True,
        },
        "toolchain_channel": {
            "required_toolchain": "nightly-2024-12-25",
            "required_host": "x86_64-unknown-linux-gnu",
            "local_toolchain_present": False,
            "local_download_cache_present": bool(
                state["rustup_download_cache_files"]
            ),
            "network_install_attempted": False,
            "reason_not_attempted": (
                "rustup installation would mutate user toolchain state while "
                "the already-demonstrated shell DNS boundary prevents fetch"
            ),
        },
        "checks": {
            "native_cbc_packages_identified": True,
            "native_cbc_download_succeeded": False,
            "system_package_install_attempted": False,
            "system_libcbc_available": False,
            "cbc_executable_available": False,
            "pinned_nightly_available": False,
            "isamore_link_attempted": False,
            "isamore_algorithm_compilation_reached": False,
            "isamore_algorithm_execution_reached": False,
        },
        "next_build_stop": {
            "class": "MISSING_OFFLINE_REGISTRY_PACKAGE",
            "package": "kiddo",
            "version": "5.2.4",
        },
        "control_executed": False,
        "source_faithful_controls_reproduced": 3,
        "controls_required": 4,
        "P1_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
        "claim_boundary": (
            "The host package index identifies Coin-OR CBC 2.10.11 packages, "
            "but a download-only, user-local probe produced no artifacts "
            "because the configured mirror cannot resolve. No system install "
            "was attempted. The pinned nightly is also absent and was not "
            "installed. No link, ISAMORE compilation, solver run, or control "
            "execution is claimed."
        ),
        "next_action": (
            "resume only with authenticated local artifacts or restored "
            "transport: exact Kiddo/math crates, the pinned Rust toolchain, "
            "and controlled Coin-OR CBC packages"
        ),
    }


def verify(payload: dict) -> None:
    validate_absence()
    probe = payload["apt_channels"]["download_probe"]
    combined = probe["stdout"] + probe["stderr"]
    if not (
        payload["status"]
        == "ISAMORE_NATIVE_LP_CHANNELS_IDENTIFIED_TRANSPORT_UNAVAILABLE"
        and payload["apt_channels"]["candidate_version"] == APT_VERSION
        and probe["returncode"] != 0
        and "Could not resolve 'apt.pop-os.org'" in combined
        and probe["downloaded_artifacts"] == []
        and probe["system_install_attempted"] is False
        and payload["toolchain_channel"]["local_toolchain_present"] is False
        and payload["toolchain_channel"]["network_install_attempted"] is False
        and payload["checks"]["system_libcbc_available"] is False
        and payload["checks"]["pinned_nightly_available"] is False
        and payload["checks"]["isamore_algorithm_execution_reached"] is False
        and payload["next_build_stop"]["package"] == "kiddo"
        and payload["control_executed"] is False
        and payload["validation_v6_accessed"] is False
    ):
        raise RuntimeError("frozen native LP acquisition boundary changed")


def main() -> None:
    if RESULT.exists():
        payload = json.loads(RESULT.read_text())
        verify(payload)
        mode = "VERIFY_FROZEN"
    else:
        payload = create()
        verify(payload)
        RESULT.write_text(canonical(payload) + "\n")
        mode = "CREATE"
    print(
        "FOUNDRY_PHASE129_ISAMORE_NATIVE_LP_ACQUISITION"
        " status=CHANNELS_IDENTIFIED_TRANSPORT_UNAVAILABLE"
        " apt_candidate=2.10.11 downloaded=false installed=false"
        " libcbc=false pinned_nightly=false linked=false executed=false"
        f" evidence={mode}"
    )


if __name__ == "__main__":
    main()
