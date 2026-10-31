#!/usr/bin/env python3
"""Create or verify the Pareto candidate and preflight protocol freeze."""

from __future__ import annotations

import ast
import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/pareto_candidate_v1_freeze.json"
RECORDS = (
    "freeze_pareto_candidate_v1.py",
    "PARETO_PROSPECTIVE_PROTOCOL_V1.json",
    "phase68_pareto_authorization_audit.py",
    "freeze_external_validation_v6.py",
    "external_validation_v6/SOURCE_INTAKE.json",
    "external_validation_v6/models.py",
    "external_validation_v6_runtime.py",
    "results/external_validation_v6_intake_freeze.json",
    "phase63_pareto_motif_calibration.py",
    "phase64_pareto_portfolio_optimizer.py",
    "independent_pareto_tool_evaluator.py",
    "phase65_independent_pareto_conformance.py",
    "phase66_pareto_native_dedup.py",
    "phase67_pareto_resource_audit.py",
    "results/pareto_tool_pool.json",
    "results/forged_pareto_tools.json",
    "results/phase63_pareto_motif_calibration.json",
    "results/phase64_pareto_portfolio_optimizer.json",
    "results/phase65_independent_pareto_conformance.json",
    "results/phase66_pareto_native_dedup.json",
    "results/phase67_pareto_resource_audit.json",
    "ATEN_FIXED_PORTFOLIO_V2.json",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows() -> list[dict[str, str]]:
    return [{"path": path, "sha256": sha(HERE / path)} for path in RECORDS]


def digest(value: list[dict[str, str]]) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def validate() -> tuple[dict, dict, dict, dict]:
    intake = json.loads(
        (HERE / "results/external_validation_v6_intake_freeze.json").read_text()
    )
    optimizer = json.loads(
        (HERE / "results/phase64_pareto_portfolio_optimizer.json").read_text()
    )
    conformance = json.loads(
        (HERE / "results/phase65_independent_pareto_conformance.json").read_text()
    )
    native = json.loads(
        (HERE / "results/phase66_pareto_native_dedup.json").read_text()
    )
    resource = json.loads(
        (HERE / "results/phase67_pareto_resource_audit.json").read_text()
    )
    if (
        intake["classification"]
        != "PROSPECTIVE_V6_SOURCE_FROZEN_PRE_CONSTRUCTION"
        or optimizer["status"] != "PARETO_PORTFOLIO_SELECTED"
        or conformance["status"] != "PARETO_INDEPENDENT_CONFORMANCE_PASS"
        or native["status"] != "PARETO_NATIVE_DEDUP_COMPLETE"
        or resource["status"] != "PARETO_RESOURCE_COMPONENT_READY"
    ):
        raise RuntimeError("Pareto candidate is not preflight-ready")
    if (HERE / "results/phase68_pareto_authorization_audit.json").exists():
        raise RuntimeError("authorization outcome exists before candidate freeze")
    ast.parse(
        (HERE / "phase68_pareto_authorization_audit.py").read_text(),
        filename="phase68_pareto_authorization_audit.py",
    )
    return intake, optimizer, conformance, native


def create() -> dict:
    if MANIFEST.exists():
        raise RuntimeError("Pareto candidate freeze already exists")
    intake, optimizer, conformance, native = validate()
    records = rows()
    payload = {
        "version": "FOUNDRY_PARETO_CANDIDATE_FREEZE_V1",
        "records": records,
        "records_sha256": digest(records),
        "classification": "PARETO_CANDIDATE_AND_PROTOCOL_FROZEN_PRE_HELDOUT",
        "heldout_intake_records_sha256": intake["records_sha256"],
        "tools": optimizer["selected"]["tools"],
        "calibration_unique_nodes": optimizer["selected"]["unique_nodes"],
        "fixed_calibration_unique_nodes": optimizer["fixed"]["unique_nodes"],
        "calibration_total_cost": optimizer["selected"]["total_cost"],
        "fixed_calibration_total_cost": optimizer["fixed"]["total_cost"],
        "independent_replays": conformance["successful_replays"],
        "runtime_inventions_admitted": native["summary"][
            "runtime_inventions_admitted"
        ],
        "heldout_execution_observed": False,
        "authorization_outcome_observed": False,
        "post_freeze_intervention_allowed": False,
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text())
    expected = {
        "version": "FOUNDRY_PARETO_CANDIDATE_FREEZE_V1",
        "classification": "PARETO_CANDIDATE_AND_PROTOCOL_FROZEN_PRE_HELDOUT",
        "tools": 4,
        "calibration_unique_nodes": 53,
        "fixed_calibration_unique_nodes": 51,
        "calibration_total_cost": 2234,
        "fixed_calibration_total_cost": 2616,
        "independent_replays": 34,
        "runtime_inventions_admitted": 0,
        "heldout_execution_observed": False,
        "authorization_outcome_observed": False,
        "post_freeze_intervention_allowed": False,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("Pareto candidate freeze classification changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("Pareto candidate record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("Pareto candidate record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"Pareto candidate mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_PARETO_CANDIDATE_V1_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
