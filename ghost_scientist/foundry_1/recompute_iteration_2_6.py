#!/usr/bin/env python3
"""Recompute readiness after the pinned Enumo source-closure audit."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_enumo_source_closure_v1 import verify as verify_enumo_freeze


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def load(name: str, version: str) -> tuple[dict, str]:
    raw = (RESULTS / name).read_bytes()
    value = json.loads(raw)
    if value["version"] != version:
        raise RuntimeError(f"{name} version mismatch")
    return value, hashlib.sha256(raw).hexdigest()


def run() -> None:
    closure_freeze = verify_enumo_freeze()
    prior, prior_sha = load(
        "readiness_iteration_2_5.json", "FOUNDRY_READINESS_ITERATION_2_5"
    )
    closure, closure_sha = load(
        "phase39_enumo_source_closure.json",
        "FOUNDRY_ENUMO_SOURCE_CLOSURE_V1",
    )
    if closure["status"] != "ENUMO_SOURCE_READY_DEPENDENCY_CLOSURE_BLOCKED":
        raise RuntimeError("Enumo source closure is not expected")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_2_6",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": prior_sha,
        "enumo_closure_records_sha256": closure_freeze["records_sha256"],
        "enumo_closure_sha256": closure_sha,
        "progress": {
            "enumo_revision_pinned": True,
            "enumo_source_checkout_complete": True,
            "enumo_source_files_exact": 18,
            "enumo_direct_dependencies_available": 10,
            "enumo_direct_dependencies_total": 21,
            "enumo_control_executed": False,
            "source_faithful_controls_reproduced": 1,
            "controls_required": 4,
            "P1_complete": False,
            "P3_complete": False,
        },
        "interpretation": (
            "The complete Enumo library source closure now exists locally and "
            "all 18 files match the pinned upstream Git blobs. The exact "
            "manifest has 21 direct dependencies; only 10 compatible series "
            "are in the offline crate cache. Missing Egg 0.9, the Rust Z3 "
            "binding, and nine other direct series prevent an executable "
            "control. System libz3 alone does not close that Rust dependency. "
            "No Enumo result was observed and the control count remains 1/4."
        ),
        "remediation": {
            "required": True,
            "next_action": (
                "audit the Babble/ISAMORE pinned dependency closure and select "
                "the smaller legitimate upstream recovery path for control two"
            ),
            "forbidden_shortcuts": [
                "do not replace Egg or Z3 semantics with Ghost code",
                "do not count source checkout as execution",
                "do not treat system libz3 as the Rust binding",
                "do not increment the control count",
            ],
        },
        "remaining_blockers": prior["remaining_blockers"],
    }
    (RESULTS / "readiness_iteration_2_6.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_2_6_NOT_READY"
        " enumo_source=18/18 enumo_deps=10/21"
        " enumo_executed=false controls=1/4"
    )


if __name__ == "__main__":
    run()
