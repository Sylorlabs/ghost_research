#!/usr/bin/env python3
"""Authenticate the locked Coin-CBC Rust bindings and preserve native stops."""

from __future__ import annotations

import ctypes.util
import hashlib
import json
import pathlib
import shutil
import tarfile
import tempfile
import tomllib

from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
SOURCE = HERE / "external_controls/isamore/source"
VENDOR = HERE / "external_controls/isamore/vendor"
COIN = VENDOR / "coin_cbc-0.1.8"
PRIOR = HERE / "results/phase127_isamore_remaining_math_source_channel_audit.json"
RESULT = HERE / "results/phase128_isamore_coin_cbc_binding_bridge_audit.json"
REVISION = "0edcbcea3a238909f296c9d78dbb3fae0190c0e9"
BLOBS = {
    "Cargo.toml": "72cb3a5b30f242134e0bd709bc25f92efe16dfbe",
    "src/lib.rs": "7ebd54dc32f2e950874ee07b9220345b98ebd025",
    "src/raw.rs": "60ad202119a51b0cfc5e5b75c33bb03040261777",
    "src/sos_constraints.rs": "5fa1fd4183eb70f59bbf4799d675b843f6eedb7c",
    "coin_cbc_sys/Cargo.toml": "17ff55d021cd0c0300037bdec2fe7233793018ce",
    "coin_cbc_sys/build.rs": "950e687fe62ff5e45de9bfb9ecd6dd83829af81f",
    "coin_cbc_sys/src/lib.rs": "4d8db6798cd5685c1190caefa489f6b72f9fcd5d",
}
LOCKED = {
    ("coin_cbc", "0.1.8"): (
        "d602045cd2e7ad02608a71492af94357f493a6f3c934ce854c03bf10fddc5780"
    ),
    ("coin_cbc_sys", "0.1.2"): (
        "085619f8bdc38e24e25c6336ecc3f2e6c0543d67566dff6daef0e32f7ac20f76"
    ),
    ("lazy_static", "1.5.0"): (
        "bbd2bcb4c963f2ddae06a2efc7e9f3591312473c50c6685e1f298068316e66fe"
    ),
    ("pkg-config", "0.3.32"): (
        "7edddbd0b52d732b21ad9a5fab5c704c14cd949e5e9a1ec5929a24fded1b904c"
    ),
}


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_blob_bytes(raw: bytes) -> str:
    return hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()


def locked_rows() -> dict[tuple[str, str], dict]:
    packages = tomllib.loads((SOURCE / "Cargo.lock").read_text())["package"]
    rows = {}
    for identity, checksum in LOCKED.items():
        name, version = identity
        matches = [
            row
            for row in packages
            if row["name"] == name and row["version"] == version
        ]
        if len(matches) != 1 or matches[0].get("checksum") != checksum:
            raise RuntimeError(f"locked identity changed: {name} {version}")
        rows[identity] = matches[0]
    return rows


def source_records() -> tuple[list[dict], str]:
    records = []
    normalized = ""
    for relative, expected in BLOBS.items():
        path = COIN / relative
        raw = path.read_bytes()
        actual = git_blob_bytes(raw)
        transport = "BYTE_EXACT_GIT_BLOB"
        if actual != expected:
            if (
                relative == "src/sos_constraints.rs"
                and raw.endswith(b"\n")
                and git_blob_bytes(raw[:-1]) == expected
            ):
                transport = "EXACT_AFTER_REMOVE_TRANSPORT_TRAILING_LF"
                normalized = relative
            else:
                raise RuntimeError(f"Coin-CBC source mismatch: {relative}")
        records.append(
            {
                "path": str(path.relative_to(HERE)),
                "repository": "KardinalAI/coin_cbc",
                "revision": REVISION,
                "git_blob_sha1": expected,
                "local_git_blob_sha1": actual,
                "local_sha256": sha256(path),
                "transport": transport,
            }
        )
    if normalized != "src/sos_constraints.rs":
        raise RuntimeError("expected disclosed line-termination staging boundary absent")
    return records, normalized


def exact_archive(name: str, version: str, checksum: str) -> pathlib.Path:
    cache = pathlib.Path.home() / ".cargo/registry/cache"
    matches = list(cache.rglob(f"{name}-{version}.crate"))
    exact = [path for path in matches if sha256(path) == checksum]
    if len(exact) != 1:
        raise RuntimeError(f"exact cached archive unavailable: {name} {version}")
    return exact[0]


def compile_binding(normalized: str) -> dict:
    cargo = shutil.which("cargo")
    if cargo is None:
        raise RuntimeError("cargo unavailable")
    lazy = exact_archive("lazy_static", "1.5.0", LOCKED[("lazy_static", "1.5.0")])
    pkg = exact_archive("pkg-config", "0.3.32", LOCKED[("pkg-config", "0.3.32")])
    with tempfile.TemporaryDirectory(prefix="foundry-coin-cbc-") as tmp:
        root = pathlib.Path(tmp)
        copied = root / "coin_cbc-0.1.8"
        shutil.copytree(COIN, copied)
        normalized_path = copied / normalized
        raw = normalized_path.read_bytes()
        normalized_path.write_bytes(raw[:-1])
        if git_blob_bytes(normalized_path.read_bytes()) != BLOBS[normalized]:
            raise RuntimeError("exact staged Coin-CBC source restoration failed")
        with tarfile.open(lazy, "r:gz") as archive:
            archive.extractall(root, filter="data")
        with tarfile.open(pkg, "r:gz") as archive:
            archive.extractall(root, filter="data")
        receipt = run_metered_tree(
            [
                str(pathlib.Path(cargo).absolute()),
                "check",
                "--offline",
                "--lib",
                "--manifest-path",
                str(copied / "Cargo.toml"),
                "--config",
                f"patch.crates-io.lazy_static.path='{root / 'lazy_static-1.5.0'}'",
                "--config",
                f"patch.crates-io.pkg-config.path='{root / 'pkg-config-0.3.32'}'",
            ],
            cwd=copied,
            wall_limit_seconds=60,
            cpu_limit_seconds=55,
            rss_limit_kib=1_000_000,
            environment={
                "RUSTUP_TOOLCHAIN": "stable",
                "CARGO_NET_OFFLINE": "true",
                "CARGO_TERM_COLOR": "never",
                "CARGO_TARGET_DIR": str(root / "target"),
                "RUST_BACKTRACE": "0",
            },
        )
    if receipt["returncode"] != 0 or receipt["termination"] != "natural":
        raise RuntimeError(
            "exact Coin-CBC Rust binding source did not compile: "
            + receipt["stderr_text"][-2000:]
        )
    return receipt


def current_native() -> dict:
    nightly = (
        pathlib.Path.home()
        / ".rustup/toolchains/nightly-2024-12-25-x86_64-unknown-linux-gnu"
    )
    return {
        "system_libcbc_present": ctypes.util.find_library("Cbc") is not None,
        "cbc_executable_present": shutil.which("cbc") is not None,
        "pinned_nightly_present": nightly.is_dir(),
        "stable_toolchain_present": shutil.which("cargo") is not None,
    }


def main() -> None:
    prior = json.loads(PRIOR.read_text())
    if not (
        prior["status"]
        == "ISAMORE_REMAINING_MATH_CHANNELS_AUDITED_NO_EXACT_SOURCE"
        and prior["accumulated_kiddo_family"]["packages_bridged"] == 4
        and prior["next_build_stop"]["package"] == "kiddo"
    ):
        raise RuntimeError("prior remaining-math boundary changed")
    locked_rows()
    records, normalized = source_records()
    root_manifest = tomllib.loads((COIN / "Cargo.toml").read_text())
    sys_manifest = tomllib.loads((COIN / "coin_cbc_sys/Cargo.toml").read_text())
    if (
        root_manifest["package"]["name"] != "coin_cbc"
        or root_manifest["package"]["version"] != "0.1.8"
        or sys_manifest["package"]["name"] != "coin_cbc_sys"
        or sys_manifest["package"]["version"] != "0.1.2"
    ):
        raise RuntimeError("Coin-CBC workspace manifest identity changed")
    native = current_native()
    if (
        native["system_libcbc_present"]
        or native["cbc_executable_present"]
        or native["pinned_nightly_present"]
    ):
        raise RuntimeError("native LP closure changed; advance this phase")
    compile_receipt = compile_binding(normalized)
    payload = {
        "version": "FOUNDRY_ISAMORE_COIN_CBC_BINDING_BRIDGE_AUDIT_V1",
        "status": "ISAMORE_COIN_CBC_RUST_BINDINGS_COMPILE_NATIVE_UNAVAILABLE",
        "bridge": {
            "repository": "KardinalAI/coin_cbc",
            "revision": REVISION,
            "release_commit_message": "v0.1.8",
            "packages": ["coin_cbc 0.1.8", "coin_cbc_sys 0.1.2"],
            "source_records": records,
            "record_count": len(records),
            "byte_exact_local_records": 6,
            "exact_staged_records": 7,
            "disclosed_staging_normalization": (
                "remove one transport-added terminal LF from "
                "src/sos_constraints.rs before verifying its upstream blob"
            ),
            "crates_io_tarball_checksums_authenticated": False,
        },
        "compile_receipt": compile_receipt,
        "native_closure": native,
        "checks": {
            "locked_rust_package_identities_authenticated": True,
            "official_release_commit_source_authenticated": True,
            "exact_source_staged_before_compile": True,
            "rust_binding_source_compilation_passed": True,
            "native_libcbc_available": False,
            "pinned_nightly_available": False,
            "link_or_solver_execution_attempted": False,
            "kiddo_family_count_advanced": False,
            "kiddo_root_source_acquired": False,
            "isamore_algorithm_compilation_reached": False,
            "isamore_algorithm_execution_reached": False,
        },
        "accumulated_kiddo_family": {
            "packages_bridged": 4,
            "packages_required": 8,
            "source_records_authenticated": 20,
        },
        "native_binding_packages_bridged": 2,
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
            "The locked coin_cbc 0.1.8 and coin_cbc_sys 0.1.2 Rust surfaces "
            "match the official v0.1.8 release commit and compile under cargo "
            "check after exact temporary staging. This does not link or run "
            "CBC. Native libCbc and the pinned nightly remain absent, Kiddo "
            "still stops resolution, and no ISAMORE algorithm executed."
        ),
        "next_action": (
            "acquire the exact Kiddo root/math sources and a controlled native "
            "CBC plus pinned-nightly closure before attempting the frozen "
            "ISAMORE conformance fixture"
        ),
    }
    if RESULT.exists():
        frozen = json.loads(RESULT.read_text())
        current = dict(payload)
        old = dict(frozen)
        current.pop("compile_receipt")
        receipt = old.pop("compile_receipt")
        if not (
            current == old
            and receipt.get("returncode") == 0
            and receipt.get("termination") == "natural"
        ):
            raise RuntimeError("rerun disagrees with frozen Coin-CBC bridge")
        mode = "VERIFY_FROZEN"
    else:
        RESULT.write_text(canonical(payload) + "\n")
        mode = "CREATE"
    print(
        "FOUNDRY_PHASE128_ISAMORE_COIN_CBC_BINDINGS"
        " status=EXACT_RELEASE_COMMIT_RUST_COMPILE records=7"
        " packages=2 native_cbc=false pinned_nightly=false"
        " linked=false solver_executed=false stop=kiddo P1=false"
        f" evidence={mode}"
    )


if __name__ == "__main__":
    main()
