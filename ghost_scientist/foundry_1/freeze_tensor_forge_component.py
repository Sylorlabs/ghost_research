#!/usr/bin/env python3
"""Create or verify the immutable Foundry tensor-forge component freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/tensor_forge_component_freeze.json"
RECORDS = (
    "ITERATION_1_5.md",
    "ITERATION_1_6.md",
    "phase9_future_tool_admission.py",
    "phase10_tensor_tool_forge.py",
    "independent_tensor_tool_evaluator.py",
    "phase12_tensor_native_resource_audit.py",
    "recompute_iteration_1_5.py",
    "recompute_iteration_1_6.py",
    "freeze_tensor_forge_component.py",
    "results/phase9_future_tool_admission.json",
    "results/readiness_iteration_1_5.json",
    "results/forged_tensor_tools.json",
    "results/phase10_tensor_forge.json",
    "results/phase11_independent_tensor_eval.json",
    "results/phase12_tensor_native_resource.json",
    "results/readiness_iteration_1_6.json",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def expected_records() -> list[dict[str, str]]:
    rows = []
    for relative in RECORDS:
        path = HERE / relative
        if not path.is_file():
            raise RuntimeError(f"freeze input missing: {relative}")
        rows.append({"path": relative, "sha256": sha(path)})
    return rows


def manifest_digest(records: list[dict[str, str]]) -> str:
    raw = json.dumps(records, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def create() -> dict:
    if MANIFEST.exists():
        raise RuntimeError("tensor component freeze already exists")
    records = expected_records()
    payload = {
        "version": "FOUNDRY_TENSOR_COMPONENT_FREEZE_V1",
        "records": records,
        "records_sha256": manifest_digest(records),
        "boundary": {
            "calibration_only": True,
            "prospective_trial_authorized": False,
            "external_controls_included": False,
            "external_workload_trace_included": False,
        },
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if set(payload) != {"version", "records", "records_sha256", "boundary"}:
        raise RuntimeError("tensor component freeze fields changed")
    if payload["version"] != "FOUNDRY_TENSOR_COMPONENT_FREEZE_V1":
        raise RuntimeError("tensor component freeze version changed")
    if payload["records_sha256"] != manifest_digest(payload["records"]):
        raise RuntimeError("tensor component record digest changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("tensor component freeze record order changed")
    for row in payload["records"]:
        if set(row) != {"path", "sha256"} or sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"tensor component freeze mismatch: {row['path']}")
    if payload["boundary"] != {
        "calibration_only": True,
        "prospective_trial_authorized": False,
        "external_controls_included": False,
        "external_workload_trace_included": False,
    }:
        raise RuntimeError("tensor component freeze boundary changed")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    mode = "VERIFY" if existed else "CREATE"
    verify()
    print(
        "FOUNDRY_TENSOR_COMPONENT_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" records_sha256={payload['records_sha256']}"
        f" mode={mode}"
    )


if __name__ == "__main__":
    main()
