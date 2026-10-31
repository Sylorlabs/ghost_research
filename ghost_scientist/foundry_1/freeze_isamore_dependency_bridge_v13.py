#!/usr/bin/env python3
"""Create or verify the exact kiddo closure census freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/isamore_dependency_bridge_v13_freeze.json"
RECORDS = (
    "results/isamore_dependency_bridge_v12_freeze.json",
    "phase123_isamore_kiddo_closure_census.py",
    "results/phase123_isamore_kiddo_closure_census.json",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows() -> list[dict[str, str]]:
    return [{"path": p, "sha256": sha(HERE / p)} for p in RECORDS]


def digest(rows_: list[dict[str, str]]) -> str:
    raw = json.dumps(rows_, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def create() -> dict:
    result = json.loads(
        (HERE / "results/phase123_isamore_kiddo_closure_census.json").read_text()
    )
    if not (
        result["status"] == "ISAMORE_KIDDO_CLOSURE_AUTHENTICATED_INCOMPLETE"
        and result["summary"]["locked_packages"] == 56
        and result["summary"]["exact_cached_archives"] == 34
        and result["summary"]["missing_exact_archives"] == 22
        and result["build_stop_after_phase"] == "kiddo"
        and result["control_executed"] is False
    ):
        raise RuntimeError("kiddo closure evidence invalid")
    records = rows()
    payload = {
        "version": "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V13",
        "records": records,
        "records_sha256": digest(records),
        "classification": "KIDDO_LOCKED_CLOSURE_CENSUS_NO_STOP_ADVANCE",
        "phases": [123],
        "closure_root": "kiddo 5.2.4",
        "locked_packages": 56,
        "exact_cached_archives": 34,
        "missing_exact_archives": 22,
        "prior_stop": "kiddo",
        "next_stop": "kiddo",
        "algorithm_compilation_reached": False,
        "algorithm_execution_reached": False,
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
    if (
        payload["version"] != "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V13"
        or payload["phases"] != [123]
        or payload["closure_root"] != "kiddo 5.2.4"
        or payload["locked_packages"] != 56
        or payload["exact_cached_archives"] != 34
        or payload["missing_exact_archives"] != 22
        or payload["next_stop"] != "kiddo"
        or payload["control_executed"] is not False
        or payload["prospective_trial_authorized"] is not False
    ):
        raise RuntimeError("kiddo closure freeze changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("kiddo closure freeze digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"kiddo closure freeze mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_V13_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
