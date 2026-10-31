#!/usr/bin/env python3
"""Create or verify the first post-authorization remediation freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/pareto_remediation_v1_freeze.json"
RECORDS = (
    "PARETO_REMEDIATION_LEDGER_V1.json",
    "external_controls/eggmind/SOURCE_INTAKE.json",
    "external_controls/eggmind/conformance_fixture_v1.json",
    "eggmind_adapted_boundary.py",
    "independent_eggmind_boundary.py",
    "phase70_eggmind_source_route_audit.py",
    "results/phase70_eggmind_source_route_audit.json",
    "phase71_eggmind_adapted_boundary_conformance.py",
    "results/phase71_eggmind_adapted_boundary_conformance.json",
    "per_instance_controls.py",
    "phase72_per_instance_control_conformance.py",
    "results/phase72_per_instance_control_conformance.json",
    "phase73_per_instance_resource_audit.py",
    "results/phase73_per_instance_resource_audit.json",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows() -> list[dict[str, str]]:
    return [{"path": path, "sha256": sha(HERE / path)} for path in RECORDS]


def records_digest(records: list[dict[str, str]]) -> str:
    raw = json.dumps(records, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def create() -> dict:
    if MANIFEST.exists():
        raise RuntimeError("Pareto remediation freeze already exists")
    source = json.loads(
        (HERE / "results/phase70_eggmind_source_route_audit.json").read_text()
    )
    boundary = json.loads(
        (
            HERE
            / "results/phase71_eggmind_adapted_boundary_conformance.json"
        ).read_text()
    )
    controls = json.loads(
        (
            HERE / "results/phase72_per_instance_control_conformance.json"
        ).read_text()
    )
    resources = json.loads(
        (
            HERE / "results/phase73_per_instance_resource_audit.json"
        ).read_text()
    )
    if not (
        source["P1"]["complete"] is False
        and boundary["P1"]["complete"] is False
        and controls["production_boundary"]["prospective_arm_complete"]
        is False
        and resources["P3"]["complete"] is False
        and controls["A3"]["validation_v6_accessed"] is False
        and controls["A9"]["validation_v6_accessed"] is False
        and resources["validation_v6_accessed"] is False
    ):
        raise RuntimeError("remediation evidence overstates completion")
    records = rows()
    payload = {
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V1",
        "records": records,
        "records_sha256": records_digest(records),
        "classification": "POST_AUTHORIZATION_REMEDIATION_NO_HELDOUT",
        "phases": [70, 71, 72, 73],
        "A3_calibration_conformance": True,
        "A8_full_conformance": False,
        "A9_calibration_conformance": True,
        "prerequisites_completed": 0,
        "prospective_trial_authorized": False,
        "heldout_source_runtime_or_graph_accessed": False,
        "heldout_execution_observed": False,
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text())
    expected = {
        "version": "FOUNDRY_PARETO_REMEDIATION_FREEZE_V1",
        "classification": "POST_AUTHORIZATION_REMEDIATION_NO_HELDOUT",
        "phases": [70, 71, 72, 73],
        "A3_calibration_conformance": True,
        "A8_full_conformance": False,
        "A9_calibration_conformance": True,
        "prerequisites_completed": 0,
        "prospective_trial_authorized": False,
        "heldout_source_runtime_or_graph_accessed": False,
        "heldout_execution_observed": False,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("Pareto remediation freeze changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("Pareto remediation record order changed")
    if payload["records_sha256"] != records_digest(payload["records"]):
        raise RuntimeError("Pareto remediation record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"Pareto remediation mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_PARETO_REMEDIATION_V1_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
