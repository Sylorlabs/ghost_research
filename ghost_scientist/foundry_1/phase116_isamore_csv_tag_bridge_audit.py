#!/usr/bin/env python3
"""Advance ISAMORE through csv's closure using exact official-tag source."""

from __future__ import annotations

import hashlib
import json
import pathlib
import shutil
import tomllib

from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
SOURCE = HERE / "external_controls/isamore/source"
VENDOR = HERE / "external_controls/isamore/vendor"
PRIOR = HERE / "results/phase115_isamore_csv_closure_census.json"
RESULT = HERE / "results/phase116_isamore_csv_tag_bridge_audit.json"
TAG_BLOBS = {
    "itoa-1.0.17/Cargo.toml": "d89b787e90c95c3dd570cd7fcdf96f8c1aeec4cf",
    "itoa-1.0.17/src/lib.rs": "5dbcf6f758d7834245e78a1d35ef82840d205bc8",
    "itoa-1.0.17/src/u128_ext.rs": "866a7334df8f6439bbc454092091b046992a8b60",
    "quote-1.0.44/Cargo.toml": "5a88a507fbc42d59fc075c842e511ee46bc48b56",
    "quote-1.0.44/src/lib.rs": "ee9928f7af7b9a23c2931b770aaff3127e4338de",
    "quote-1.0.44/src/ext.rs": "2553717f905253d5a7cb39b828612f11d3419473",
    "quote-1.0.44/src/format.rs": "894d146c5733e5833881885c110c0bf029af8963",
    "quote-1.0.44/src/ident_fragment.rs": "646c9c7d8c9692feecca82135997771bdc506ccf",
    "quote-1.0.44/src/to_tokens.rs": "aec6d2bba8e22f8d1a5dc97d5c117fc314db12aa",
    "quote-1.0.44/src/runtime.rs": "46bba332c11728eee831ed81fa2c7e944d03a1d7",
    "quote-1.0.44/src/spanned.rs": "6afc6b3035597731e3f42a13df1a00647918f134",
    "csv-1.4.0/Cargo.toml": "7101062c1acf68564fd9a22df01d7f5837a0b682",
    "csv-1.4.0/src/lib.rs": "28ff12adbefe8915611124a09a4eab8fe5b47101",
    "csv-1.4.0/src/byte_record.rs": "c6c196e433db8dc2c91fab90b097215c5e55987f",
    "csv-1.4.0/src/cookbook.rs": "4d3a5775ced968368b1d4c48f2194a37c19f3c70",
    "csv-1.4.0/src/debug.rs": "5001b04d94c405bf149ef386be726d3267ef22b6",
    "csv-1.4.0/src/deserializer.rs": "c7c321784e0db3d6e2122790368477e704d8434b",
    "csv-1.4.0/src/error.rs": "8ffc181bb93955968f76093e58a628a8b032c341",
    "csv-1.4.0/src/reader.rs": "a34c9d5a508d2d52e967d34011f4075bafde161c",
    "csv-1.4.0/src/serializer.rs": "a3f9ff827d220b0a8d34aa2fd10718309adf9d00",
    "csv-1.4.0/src/string_record.rs": "d9001e243b5e3631542cfbad71696a55aa206ee6",
    "csv-1.4.0/src/tutorial.rs": "4682053496f7ea4eae8caf7859e3f0d1d0b23478",
    "csv-1.4.0/src/writer.rs": "195e663e4fef559f617efbdee9749b2268843682",
    "csv-1.4.0/csv-core/Cargo.toml": "a7404c204c05b9637d9ee578b7ca8746d6e10673",
    "csv-1.4.0/csv-core/src/lib.rs": "1e41cb5da73ec26583a0ed8b8a5e60a0fbd1412f",
    "csv-1.4.0/csv-core/src/reader.rs": "5bcbdfaab63e6aad3eeeccb9c7bd54af544995e8",
    "csv-1.4.0/csv-core/src/writer.rs": "011ab065843c0b5e5a68e807c9859d4c19e98cd7",
}


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_blob(path: pathlib.Path) -> str:
    raw = path.read_bytes()
    return hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()


def main() -> None:
    prior = json.loads(PRIOR.read_text(encoding="utf-8"))
    if not (
        prior["status"] == "ISAMORE_CSV_CLOSURE_AUTHENTICATED_INCOMPLETE"
        and prior["summary"]["missing_exact_archives"] == 4
        and prior["build_stop_after_phase"] == "csv"
    ):
        raise RuntimeError("prior csv census changed")

    records = []
    for relative, expected_blob in TAG_BLOBS.items():
        path = VENDOR / relative
        actual_blob = git_blob(path)
        if actual_blob != expected_blob:
            raise RuntimeError(f"official-tag blob mismatch: {relative}")
        records.append(
            {
                "path": str(path.relative_to(HERE)),
                "git_blob_sha1": actual_blob,
                "sha256": sha256(path),
            }
        )

    manifests = {
        "csv": tomllib.loads((VENDOR / "csv-1.4.0/Cargo.toml").read_text()),
        "csv-core": tomllib.loads(
            (VENDOR / "csv-1.4.0/csv-core/Cargo.toml").read_text()
        ),
        "itoa": tomllib.loads(
            (VENDOR / "itoa-1.0.17/Cargo.toml").read_text()
        ),
        "quote": tomllib.loads(
            (VENDOR / "quote-1.0.44/Cargo.toml").read_text()
        ),
    }
    expected_versions = {
        "csv": "1.4.0",
        "csv-core": "0.1.13",
        "itoa": "1.0.17",
        "quote": "1.0.44",
    }
    for package, expected in expected_versions.items():
        if manifests[package]["package"]["version"] != expected:
            raise RuntimeError(f"official-tag version mismatch: {package}")

    cargo = shutil.which("cargo")
    if cargo is None:
        raise RuntimeError("cargo unavailable")
    receipt = run_metered_tree(
        [
            str(pathlib.Path(cargo).absolute()),
            "--config",
            'patch.crates-io.colored.path="../vendor/colored-3.1.1"',
            "--config",
            'patch.crates-io.crossbeam.path="../vendor/crossbeam-0.8.4"',
            "--config",
            'patch.crates-io.csv.path="../vendor/csv-1.4.0"',
            "--config",
            'patch.crates-io.csv-core.path="../vendor/csv-1.4.0/csv-core"',
            "--config",
            'patch.crates-io.itoa.path="../vendor/itoa-1.0.17"',
            "--config",
            'patch.crates-io.quote.path="../vendor/quote-1.0.44"',
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
        and "no matching package named `env_logger` found"
        in receipt["stderr_text"]
    )
    csv_stop_cleared = (
        "no matching package named `csv` found" not in receipt["stderr_text"]
    )
    if not next_stop or not csv_stop_cleared:
        raise RuntimeError(
            "csv tag bridge did not advance expected stop: "
            + receipt["stderr_text"]
        )

    payload = {
        "version": "FOUNDRY_ISAMORE_CSV_TAG_BRIDGE_AUDIT_V1",
        "status": "ISAMORE_CSV_CLOSURE_ADVANCES_STOP",
        "bridge": {
            "packages": expected_versions,
            "repositories": {
                "csv_and_csv_core": "BurntSushi/rust-csv",
                "itoa": "dtolnay/itoa",
                "quote": "dtolnay/quote",
            },
            "tags": {
                "csv_and_csv_core": "1.4.0",
                "itoa": "1.0.17",
                "quote": "1.0.44",
            },
            "official_tag_records": records,
            "crates_io_tarball_checksums_authenticated": False,
            "classification": "EXACT_OFFICIAL_TAG_SOURCE_BRIDGE",
        },
        "receipt": receipt,
        "checks": {
            "twenty_seven_source_records_exact_to_official_tags": True,
            "manifest_versions_match_lock": True,
            "nearby_versions_substituted": False,
            "csv_stop_cleared": csv_stop_cleared,
            "next_missing_package_authenticated": next_stop,
            "algorithm_compilation_reached": False,
            "algorithm_execution_reached": False,
        },
        "next_build_stop": {
            "class": "MISSING_OFFLINE_REGISTRY_PACKAGE",
            "package": "env_logger",
            "authenticated_by_cargo": True,
        },
        "control_executed": False,
        "source_faithful_controls_reproduced": 3,
        "controls_required": 4,
        "P1_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
        "claim_boundary": (
            "Exact official release-tag source for csv, csv-core, itoa, and "
            "quote advances the metered build stop to env_logger. This does "
            "not reproduce crates.io tarball checksums, and no ISAMORE "
            "algorithm compiled or executed."
        ),
        "next_action": (
            "audit the exact locked env_logger transitive closure before "
            "attempting another authenticated bridge"
        ),
    }
    if RESULT.exists():
        frozen = json.loads(RESULT.read_text(encoding="utf-8"))
        frozen_receipt = frozen.get("receipt", {})
        frozen_semantics = dict(frozen)
        current_semantics = dict(payload)
        frozen_semantics.pop("receipt", None)
        current_semantics.pop("receipt", None)
        frozen_stop_is_valid = (
            frozen_receipt.get("returncode") != 0
            and frozen_receipt.get("termination") == "natural"
            and "no matching package named `env_logger` found"
            in frozen_receipt.get("stderr_text", "")
        )
        if frozen_semantics != current_semantics or not frozen_stop_is_valid:
            raise RuntimeError("rerun disagrees with frozen csv bridge evidence")
        mode = "VERIFY_FROZEN"
    else:
        RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
        mode = "CREATE"
    print(
        "FOUNDRY_PHASE116_ISAMORE_CSV_TAG_BRIDGE"
        " status=ADVANCES_STOP records=27 next_stop=env_logger"
        " compiled=false executed=false controls=3/4 P1=false"
        f" evidence={mode}"
    )


if __name__ == "__main__":
    main()
