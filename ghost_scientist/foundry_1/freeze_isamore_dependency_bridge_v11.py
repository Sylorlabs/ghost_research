#!/usr/bin/env python3
"""Create or verify the indicatif closure census freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/isamore_dependency_bridge_v11_freeze.json"
RECORDS = (
    "results/isamore_dependency_bridge_v10_freeze.json",
    "phase121_isamore_indicatif_closure_census.py",
    "results/phase121_isamore_indicatif_closure_census.json",
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
        (
            HERE / "results/phase121_isamore_indicatif_closure_census.json"
        ).read_text()
    )
    if not (
        result["status"]
        == "ISAMORE_INDICATIF_CLOSURE_AUTHENTICATED_INCOMPLETE"
        and result["summary"]["locked_packages"] == 31
        and result["summary"]["exact_cached_archives"] == 18
        and result["summary"]["missing_exact_archives"] == 13
        and result["build_stop_after_phase"] == "indicatif"
        and result["control_executed"] is False
    ):
        raise RuntimeError("indicatif closure evidence invalid")
    records = rows()
    payload = {
        "version": "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V11",
        "records": records,
        "records_sha256": digest(records),
        "classification": "INDICATIF_LOCKED_CLOSURE_CENSUS_NO_STOP_ADVANCE",
        "phases": [121],
        "closure_root": "indicatif 0.17.11",
        "locked_packages": 31,
        "exact_cached_archives": 18,
        "missing_exact_archives": 13,
        "prior_stop": "indicatif",
        "next_stop": "indicatif",
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
        payload["version"] != "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_FREEZE_V11"
        or payload["phases"] != [121]
        or payload["closure_root"] != "indicatif 0.17.11"
        or payload["locked_packages"] != 31
        or payload["exact_cached_archives"] != 18
        or payload["missing_exact_archives"] != 13
        or payload["next_stop"] != "indicatif"
        or payload["control_executed"] is not False
        or payload["prospective_trial_authorized"] is not False
    ):
        raise RuntimeError("indicatif closure freeze changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("indicatif closure freeze digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"indicatif freeze mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_ISAMORE_DEPENDENCY_BRIDGE_V11_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
