#!/usr/bin/env python3
"""Recompute Foundry-1.3 after external-control source intake."""

from __future__ import annotations

import json
import pathlib

from independent_evaluator import canonical_json, file_sha256_bytes


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_1_2.json"
    intake_path = RESULTS / "phase7_control_intake.json"
    prior = json.loads(prior_path.read_text(encoding="utf-8"))
    intake = json.loads(intake_path.read_text(encoding="utf-8"))
    if prior["verdict"] != "FOUNDRY_V6_NOT_READY":
        raise RuntimeError("prior iteration did not fail closed")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_1_3",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": file_sha256_bytes(prior_path.read_bytes()),
        "control_intake_sha256": file_sha256_bytes(intake_path.read_bytes()),
        "progress": {
            "P1_source_intake_component": intake["P1_source_intake_component"],
            "P1_repository_records_pinned": intake["repository_records_pinned"],
            "P1_conformance_executed": intake["conformance_executed"],
            "P1_complete": intake["P1_complete"],
        },
        "remaining_blockers": [
            "obtain executable pinned checkouts for Stitch, Babble/ISAMORE, Ruler/Enumo, and EggMind",
            "run paper-derived conformance fixtures before adapting controls",
            "add heterogeneous application workloads and an independent invocation trace",
            "integrate complete process-tree metering and future-tool native deduplication",
            "resolve the strong-fixed tie without weakening the fixed portfolio",
        ],
        "interpretation": (
            "The external-control identities, revisions, and defining fixtures are now "
            "bounded, but no upstream executable has been reproduced. P1 remains false."
        ),
    }
    (RESULTS / "readiness_iteration_1_3.json").write_text(
        canonical_json(payload) + "\n", encoding="utf-8"
    )
    print(
        "FOUNDRY_1_3_NOT_READY"
        f" p1_intake={'PASS' if intake['P1_source_intake_component'] else 'FAIL'}"
        f" conformance={intake['conformance_executed']}/4"
    )


if __name__ == "__main__":
    main()

