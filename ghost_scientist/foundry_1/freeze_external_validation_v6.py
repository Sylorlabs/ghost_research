#!/usr/bin/env python3
"""Create or verify the pre-construction v6 validation source freeze."""

from __future__ import annotations

import ast
import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/external_validation_v6_intake_freeze.json"
RECORDS = (
    "freeze_external_validation_v6.py",
    "external_validation_v6/SOURCE_INTAKE.json",
    "external_validation_v6/models.py",
    "external_validation_v6_runtime.py",
    "external_validation_v6/LICENSE.brain-segmentation-pytorch",
    "external_validation_v6/LICENSE.pytorch-seq2seq",
    "external_validation_v6/LICENSE.spotlight",
    "external_validation_v6/LICENSE.tcn",
    "results/diversity_failure_calibration_v1_freeze.json",
    "ATEN_FIXED_PORTFOLIO_V2.json",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows() -> list[dict[str, str]]:
    return [{"path": path, "sha256": sha(HERE / path)} for path in RECORDS]


def digest(value: list[dict[str, str]]) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def validate_preconstruction_intake() -> dict:
    intake = json.loads(
        (HERE / "external_validation_v6/SOURCE_INTAKE.json").read_text()
    )
    if any(intake["selection_boundary"].values()):
        raise RuntimeError("v6 intake no longer precedes candidate construction")
    sources = intake["sources"]
    repositories = {item["repository"] for item in sources}
    domains = {item["semantic_domain"] for item in sources}
    excluded = set(
        intake["selection_rule"]["calibration_repositories_excluded"]
    )
    if len(sources) != 4 or len(repositories) != 4 or len(domains) != 4:
        raise RuntimeError("v6 source diversity contract failed")
    if repositories & excluded:
        raise RuntimeError("v6 repository overlaps calibration")
    if any(item["license"] != "MIT" for item in sources):
        raise RuntimeError("v6 license contract changed")
    for path in (
        "external_validation_v6/models.py",
        "external_validation_v6_runtime.py",
    ):
        ast.parse((HERE / path).read_text(), filename=path)
    return intake


def create() -> dict:
    if MANIFEST.exists():
        raise RuntimeError("v6 validation intake freeze already exists")
    intake = validate_preconstruction_intake()
    records = rows()
    payload = {
        "version": "FOUNDRY_EXTERNAL_VALIDATION_V6_INTAKE_FREEZE",
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
        "pareto_candidate_records_constructed": False,
        "candidate_or_fixed_execution_observed": False,
        "validation_graphs_exported_or_inspected": False,
        "validation_runtime_executed": False,
        "classification": "PROSPECTIVE_V6_SOURCE_FROZEN_PRE_CONSTRUCTION",
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    return payload


def verify() -> dict:
    validate_preconstruction_intake()
    payload = json.loads(MANIFEST.read_text())
    expected = {
        "version": "FOUNDRY_EXTERNAL_VALIDATION_V6_INTAKE_FREEZE",
        "source_count": 4,
        "repository_count": 4,
        "semantic_domain_count": 4,
        "transformer_or_attention_count": 0,
        "pareto_candidate_records_constructed": False,
        "candidate_or_fixed_execution_observed": False,
        "validation_graphs_exported_or_inspected": False,
        "validation_runtime_executed": False,
        "classification": "PROSPECTIVE_V6_SOURCE_FROZEN_PRE_CONSTRUCTION",
    }
    if any(payload[key] != value for key, value in expected.items()):
        raise RuntimeError("v6 validation intake classification changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("v6 intake record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("v6 intake record digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"v6 intake mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_EXTERNAL_VALIDATION_V6_INTAKE_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
