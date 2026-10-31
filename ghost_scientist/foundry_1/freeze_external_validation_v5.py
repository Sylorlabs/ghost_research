#!/usr/bin/env python3
"""Create or verify the pre-execution v5 validation intake freeze."""

from __future__ import annotations

import ast
import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/external_validation_v5_intake_freeze.json"
RECORDS = (
    "freeze_external_validation_v5.py",
    "external_validation_v5/SOURCE_INTAKE.json",
    "external_validation_v5/models.py",
    "external_validation_v5_runtime.py",
    "external_validation_v5/LICENSE.jcjohnson-pytorch-examples",
    "external_validation_v5/LICENSE.pytorch-tutorials",
    "external_validation_v5/LICENSE.yunjey-pytorch-tutorial",
    "external_validation_v5/LICENSE.udacity-deep-learning-v2-pytorch",
    "results/diversity_calibration_v1_freeze.json",
    "ATEN_FIXED_PORTFOLIO_V2.json",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows() -> list[dict[str, str]]:
    return [{"path": path, "sha256": sha(HERE / path)} for path in RECORDS]


def digest(value: list[dict[str, str]]) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def validate_pre_execution_intake() -> dict:
    intake = json.loads(
        (HERE / "external_validation_v5/SOURCE_INTAKE.json").read_text()
    )
    boundary = intake["selection_boundary"]
    if any(boundary.values()):
        raise RuntimeError("v5 intake no longer represents a pre-execution boundary")
    sources = intake["sources"]
    repos = {item["repository"] for item in sources}
    domains = {item["semantic_domain"] for item in sources}
    excluded = set(intake["selection_rule"]["calibration_repositories_excluded"])
    if len(sources) != 4 or len(repos) != 4 or len(domains) != 4:
        raise RuntimeError("v5 intake diversity contract failed")
    if repos & excluded:
        raise RuntimeError("v5 intake overlaps a calibration repository")
    for path in ("external_validation_v5/models.py", "external_validation_v5_runtime.py"):
        ast.parse((HERE / path).read_text(), filename=path)
    return intake


def create() -> dict:
    if MANIFEST.exists():
        raise RuntimeError("v5 validation intake freeze already exists")
    intake = validate_pre_execution_intake()
    records = rows()
    payload = {
        "version": "FOUNDRY_EXTERNAL_VALIDATION_V5_INTAKE_FREEZE",
        "records": records,
        "records_sha256": digest(records),
        "source_count": len(intake["sources"]),
        "repository_count": len(
            {item["repository"] for item in intake["sources"]}
        ),
        "semantic_domain_count": len(
            {item["semantic_domain"] for item in intake["sources"]}
        ),
        "transformer_or_attention_count": 0,
        "candidate_typed_records_constructed": False,
        "candidate_or_fixed_execution_observed": False,
        "validation_graphs_exported_or_inspected": False,
        "validation_runtime_executed": False,
        "classification": "PROSPECTIVE_SOURCE_INTAKE_FROZEN_PRE_EXECUTION",
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    return payload


def verify() -> dict:
    validate_pre_execution_intake()
    payload = json.loads(MANIFEST.read_text())
    expected = {
        "version": "FOUNDRY_EXTERNAL_VALIDATION_V5_INTAKE_FREEZE",
        "source_count": 4,
        "repository_count": 4,
        "semantic_domain_count": 4,
        "transformer_or_attention_count": 0,
        "candidate_typed_records_constructed": False,
        "candidate_or_fixed_execution_observed": False,
        "validation_graphs_exported_or_inspected": False,
        "validation_runtime_executed": False,
        "classification": "PROSPECTIVE_SOURCE_INTAKE_FROZEN_PRE_EXECUTION",
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("v5 validation intake classification changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("v5 validation intake record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("v5 validation intake record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"v5 intake mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_EXTERNAL_VALIDATION_V5_INTAKE_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
