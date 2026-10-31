#!/usr/bin/env python3
"""Create or verify the Coin-CBC Rust-binding source freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/isamore_dependency_bridge_v18_freeze.json"
RECORDS = (
    "results/isamore_dependency_bridge_v17_freeze.json",
    "phase128_isamore_coin_cbc_binding_bridge_audit.py",
    "results/phase128_isamore_coin_cbc_binding_bridge_audit.json",
    "external_controls/isamore/vendor/coin_cbc-0.1.8/Cargo.toml",
    "external_controls/isamore/vendor/coin_cbc-0.1.8/src/lib.rs",
    "external_controls/isamore/vendor/coin_cbc-0.1.8/src/raw.rs",
    "external_controls/isamore/vendor/coin_cbc-0.1.8/src/sos_constraints.rs",
    "external_controls/isamore/vendor/coin_cbc-0.1.8/coin_cbc_sys/Cargo.toml",
    "external_controls/isamore/vendor/coin_cbc-0.1.8/coin_cbc_sys/build.rs",
    "external_controls/isamore/vendor/coin_cbc-0.1.8/coin_cbc_sys/src/lib.rs",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows() -> list[dict[str, str]]:
    return [{"path": path, "sha256": sha(HERE / path)} for path in RECORDS]


def digest(records: list[dict[str, str]]) -> str:
    raw = json.dumps(records, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def create() -> dict:
    result = json.loads(
        (
            HERE / "results/phase128_isamore_coin_cbc_binding_bridge_audit.json"
        ).read_text()
    )
    if not (
        result["status"]
        == "ISAMORE_COIN_CBC_RUST_BINDINGS_COMPILE_NATIVE_UNAVAILABLE"
        and result["bridge"]["record_count"] == 7
        and result["bridge"]["exact_staged_records"] == 7
        and result["checks"]["rust_binding_source_compilation_passed"] is True
        and result["checks"]["native_libcbc_available"] is False
        and result["checks"]["pinned_nightly_available"] is False
        and result["next_build_stop"]["package"] == "kiddo"
        and result["control_executed"] is False
    ):
        raise RuntimeError("Coin-CBC binding evidence invalid")
    records = rows()
    payload = {
        "version": "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V18",
        "records": records,
        "records_sha256": digest(records),
        "classification": "EXACT_COIN_CBC_RUST_BINDINGS_NATIVE_UNAVAILABLE",
        "phases": [128],
        "bridged_packages": ["coin_cbc 0.1.8", "coin_cbc_sys 0.1.2"],
        "source_records": 7,
        "byte_exact_local_records": 6,
        "exact_staged_records": 7,
        "independent_source_compilation_passed": True,
        "native_libcbc_available": False,
        "pinned_nightly_available": False,
        "solver_executed": False,
        "accumulated_kiddo_family_packages": 4,
        "accumulated_kiddo_family_required": 8,
        "accumulated_kiddo_family_source_records": 20,
        "prior_stop": "kiddo",
        "next_stop": "kiddo",
        "isamore_algorithm_compilation_reached": False,
        "isamore_algorithm_execution_reached": False,
        "control_executed": False,
        "P1_complete": False,
        "prospective_trial_authorized": False,
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text())
    if not (
        payload["version"] == "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V18"
        and payload["phases"] == [128]
        and payload["bridged_packages"]
        == ["coin_cbc 0.1.8", "coin_cbc_sys 0.1.2"]
        and payload["source_records"] == 7
        and payload["byte_exact_local_records"] == 6
        and payload["exact_staged_records"] == 7
        and payload["independent_source_compilation_passed"] is True
        and payload["native_libcbc_available"] is False
        and payload["pinned_nightly_available"] is False
        and payload["solver_executed"] is False
        and payload["accumulated_kiddo_family_packages"] == 4
        and payload["prior_stop"] == "kiddo"
        and payload["next_stop"] == "kiddo"
        and payload["control_executed"] is False
        and payload["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("Coin-CBC binding freeze changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("Coin-CBC binding freeze digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"Coin-CBC freeze mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_V18_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
