#!/usr/bin/env python3
"""Recompute the post-remediation Foundry-1.1 boundary."""

from __future__ import annotations

import json
import pathlib

from independent_evaluator import canonical_json, file_sha256_bytes


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def main() -> None:
    base = json.loads((RESULTS / "readiness.json").read_text(encoding="utf-8"))
    dedup = json.loads((RESULTS / "phase4_tensor_dedup.json").read_text(encoding="utf-8"))
    if base["verdict"] != "FOUNDRY_V6_NOT_READY":
        raise RuntimeError("iteration expected a fail-closed base verdict")
    if dedup["version"] != "FOUNDRY_TENSOR_DEDUP_AUDIT_V1":
        raise RuntimeError("dedup result schema mismatch")
    summary = dedup["summary"]
    component_pass = (
        summary["plans"] == 24
        and summary["inductor_receipts_completed"]
        + summary["inductor_required_unsupported"]
        == summary["representative_signatures"]
    )
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_1_1",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "base_readiness_sha256": file_sha256_bytes(
            (RESULTS / "readiness.json").read_bytes()
        ),
        "tensor_dedup_sha256": file_sha256_bytes(
            (RESULTS / "phase4_tensor_dedup.json").read_bytes()
        ),
        "progress": {
            "P5_audit_component_executes": component_pass,
            "P5_duplicate_witnesses_found": summary["normalized_inductor_duplicates"],
            "P5_sparse_required_unsupported": summary["inductor_required_unsupported"],
            "P5_complete_for_future_foundry_tools": False,
        },
        "remaining_blockers": [
            "faithful external control implementations",
            "independently sourced tensor/compiler corpus and invocation trace",
            "complete process-tree resource metering integrated around every arm",
            "complete native-equivalence decision for future candidate tools",
            "strong fixed portfolio not beaten in the local calibration",
        ],
        "interpretation": (
            "Iteration 1.1 moved native deduplication from a paper requirement to an "
            "executed v5.1 compiler-code audit, but its sufficient equality test is not "
            "a complete equivalence decision and cannot authorize v6."
        ),
    }
    (RESULTS / "readiness_iteration_1_1.json").write_text(
        canonical_json(payload) + "\n", encoding="utf-8"
    )
    print(
        "FOUNDRY_1_1_NOT_READY"
        f" p5_component={'PASS' if component_pass else 'FAIL'}"
        f" duplicate_witnesses={summary['normalized_inductor_duplicates']}"
    )


if __name__ == "__main__":
    main()
