#!/usr/bin/env python3
"""Audit whether a source-faithful EggMind control can be acquired."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
INTAKE = HERE / "external_controls/eggmind/SOURCE_INTAKE.json"
RESULT = HERE / "results/phase70_eggmind_source_route_audit.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def run() -> None:
    raw = INTAKE.read_bytes()
    intake = json.loads(raw)
    searches = intake["artifact_searches"]
    decision = intake["decision"]
    checks = {
        "paper_identity_version_pinned": (
            intake["paper"]["arxiv_id"] == "2604.17364v1"
            and intake["paper"]["submitted_utc"]
            == "2026-04-19T10:21:26Z"
        ),
        "paper_license_recorded": intake["paper"]["license"] == "CC BY 4.0",
        "open_source_claim_recorded": intake["paper_claims"][
            "calls_framework_open_source"
        ],
        "formal_eqsatl_boundary_recorded": intake["paper_claims"][
            "formal_eqsatl_syntax_published"
        ],
        "multiple_artifact_routes_checked": len(searches) >= 6,
        "zero_official_repository_matches": all(
            not row["matching_official_repositories"] for row in searches
        ),
        "no_source_faithful_label_without_source": (
            decision["upstream_source_available"] is False
            and decision["source_faithful_label_allowed"] is False
            and decision["required_label"] == "ADAPTED"
        ),
        "a8_not_prematurely_completed": (
            decision["a8_conformance_complete"] is False
            and decision["upstream_execution_authorized"] is False
        ),
    }
    if not all(checks.values()):
        raise RuntimeError("EggMind source-route intake is internally invalid")
    payload = {
        "version": "FOUNDRY_EGGMIND_SOURCE_ROUTE_AUDIT_V1",
        "status": "EGGMIND_UPSTREAM_SOURCE_NOT_DISCOVERED",
        "classification": "SOURCE_ROUTE_EXHAUSTED_ADAPTATION_REQUIRED",
        "intake_sha256": hashlib.sha256(raw).hexdigest(),
        "search_routes": len(searches),
        "official_repository_matches": 0,
        "checks": checks,
        "P1": {
            "eggmind_upstream_control_available": False,
            "paper_derived_adaptation_permitted": True,
            "adapted_conformance_executed": False,
            "complete": False,
        },
        "remediation": {
            "next": (
                "freeze paper-derived EqSatL fixtures and implement an "
                "independently checkable ADAPTED boundary"
            ),
            "prohibited": [
                "do not call a local implementation EggMind",
                "do not infer an upstream license for unreleased code",
                "do not count syntax parsing as full strategy-synthesis conformance",
                "do not open validation-v6 while authorization remains false",
            ],
        },
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE70_EGGMIND_SOURCE_ROUTE"
        f" status={payload['status']}"
        f" routes={len(searches)}"
        " official_repositories=0"
        " a8_complete=false"
    )


if __name__ == "__main__":
    run()
