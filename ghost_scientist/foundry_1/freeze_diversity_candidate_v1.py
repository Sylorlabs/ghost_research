#!/usr/bin/env python3
"""Create or verify the candidate and prospective-protocol freeze."""

from __future__ import annotations

import ast
import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/diversity_candidate_v1_freeze.json"
RECORDS = (
    "freeze_diversity_candidate_v1.py",
    "phase55_diversity_tool_forge.py",
    "independent_diversity_tool_evaluator.py",
    "phase56_independent_diversity_conformance.py",
    "phase57_diversity_native_dedup.py",
    "phase58_diversity_resource_audit.py",
    "phase59_prospective_diversity_trial.py",
    "phase60_prospective_diversity_resource_audit.py",
    "external_validation_v5_runtime.py",
    "external_validation_v5/models.py",
    "external_validation_v5/SOURCE_INTAKE.json",
    "ATEN_FIXED_PORTFOLIO_V2.json",
    "results/external_validation_v5_intake_freeze.json",
    "results/diversity_calibration_v1_freeze.json",
    "results/forged_diversity_tools.json",
    "results/phase55_diversity_tool_forge.json",
    "results/phase56_independent_diversity_conformance.json",
    "results/phase57_diversity_native_dedup.json",
    "results/phase58_diversity_resource_audit.json",
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
        (HERE / "results/external_validation_v5_intake_freeze.json").read_text()
    )
    forge = json.loads(
        (HERE / "results/phase55_diversity_tool_forge.json").read_text()
    )
    conformance = json.loads(
        (
            HERE
            / "results/phase56_independent_diversity_conformance.json"
        ).read_text()
    )
    native = json.loads(
        (HERE / "results/phase57_diversity_native_dedup.json").read_text()
    )
    resource = json.loads(
        (HERE / "results/phase58_diversity_resource_audit.json").read_text()
    )
    if (
        intake["classification"]
        != "PROSPECTIVE_SOURCE_INTAKE_FROZEN_PRE_EXECUTION"
        or forge["status"] != "DIVERSITY_TOOL_FORGE_READY"
        or conformance["status"]
        != "DIVERSITY_TOOL_INDEPENDENT_CONFORMANCE_PASS"
        or native["status"] != "DIVERSITY_NATIVE_DEDUP_COMPLETE"
        or resource["status"] != "DIVERSITY_RESOURCE_COMPONENT_READY"
    ):
        raise RuntimeError("diversity candidate is not trial-ready")
    for path in (
        "phase59_prospective_diversity_trial.py",
        "phase60_prospective_diversity_resource_audit.py",
    ):
        ast.parse((HERE / path).read_text(), filename=path)
    for outcome in (
        "results/phase59_prospective_diversity_trial.json",
        "results/phase60_prospective_diversity_resource_audit.json",
    ):
        if (HERE / outcome).exists():
            raise RuntimeError("prospective outcome exists before protocol freeze")
    return intake, forge, conformance, native


def create() -> dict:
    if MANIFEST.exists():
        raise RuntimeError("diversity candidate freeze already exists")
    intake, forge, conformance, native = validate()
    records = rows()
    payload = {
        "version": "FOUNDRY_DIVERSITY_CANDIDATE_FREEZE_V1",
        "records": records,
        "records_sha256": digest(records),
        "classification": "PROSPECTIVE_PROTOCOL_FROZEN_PRE_OUTCOME",
        "source_intake_records_sha256": intake["records_sha256"],
        "tools_forged": forge["tools_forged"],
        "independent_replays": conformance["successful_replays"],
        "native_runtime_inventions_admitted": native["summary"][
            "runtime_inventions_admitted"
        ],
        "semantic_search_candidates": native["summary"][
            "semantic_search_candidates_retained"
        ],
        "prospective_outcomes_observed": False,
        "post_freeze_intervention_allowed": False,
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text())
    expected = {
        "version": "FOUNDRY_DIVERSITY_CANDIDATE_FREEZE_V1",
        "classification": "PROSPECTIVE_PROTOCOL_FROZEN_PRE_OUTCOME",
        "tools_forged": 3,
        "independent_replays": 21,
        "native_runtime_inventions_admitted": 0,
        "semantic_search_candidates": 3,
        "prospective_outcomes_observed": False,
        "post_freeze_intervention_allowed": False,
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("diversity candidate classification changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("diversity candidate record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("diversity candidate record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"diversity candidate mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_DIVERSITY_CANDIDATE_V1_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
