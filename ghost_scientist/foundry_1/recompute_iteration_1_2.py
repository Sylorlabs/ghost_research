#!/usr/bin/env python3
"""Recompute Foundry-1.2 after external-corpus intake."""

from __future__ import annotations

import json
import pathlib

from independent_evaluator import canonical_json, file_sha256_bytes


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def main() -> None:
    prior = json.loads(
        (RESULTS / "readiness_iteration_1_1.json").read_text(encoding="utf-8")
    )
    corpus = json.loads((RESULTS / "phase6_external_corpus.json").read_text(encoding="utf-8"))
    if prior["verdict"] != "FOUNDRY_V6_NOT_READY":
        raise RuntimeError("prior iteration did not fail closed")
    if corpus["version"] != "FOUNDRY_EXTERNAL_CORPUS_INTAKE_V1":
        raise RuntimeError("external corpus schema mismatch")
    summary = corpus["summary"]
    component = corpus["P2"]["independently_authored_pinned_corpus_component"]
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_1_2",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": file_sha256_bytes(
            (RESULTS / "readiness_iteration_1_1.json").read_bytes()
        ),
        "external_corpus_sha256": file_sha256_bytes(
            (RESULTS / "phase6_external_corpus.json").read_bytes()
        ),
        "progress": {
            "P2_external_corpus_component": component,
            "P2_exported_graphs": summary["exported"],
            "P2_unique_graphs": summary["unique_graphs"],
            "P2_application_families": False,
            "P2_independent_invocation_trace": False,
            "P2_complete": False,
        },
        "remaining_blockers": prior["remaining_blockers"],
        "interpretation": (
            "An independently authored and wheel-pinned PyTorch Export corpus is now "
            "machine-extracted, but it is compiler conformance material rather than a "
            "heterogeneous application workload with an independent invocation trace."
        ),
    }
    (RESULTS / "readiness_iteration_1_2.json").write_text(
        canonical_json(payload) + "\n", encoding="utf-8"
    )
    print(
        "FOUNDRY_1_2_NOT_READY"
        f" p2_corpus_component={'PASS' if component else 'FAIL'}"
        f" graphs={summary['exported']} invocation_trace=false"
    )


if __name__ == "__main__":
    main()

