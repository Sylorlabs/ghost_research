#!/usr/bin/env python3
"""Execute the mandatory post-transfer failed-prerequisite remediation audit."""

from __future__ import annotations

import json
import pathlib
import sys

from freeze_foundry_1 import verify
from independent_evaluator import canonical_json, file_sha256_bytes
from resource_meter import selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULTS = HERE / "results"


def _find_upstream_implementations() -> dict[str, list[str]]:
    needles = {
        "stitch": ("stitch",),
        "babble_isamore": ("babble", "isamore"),
        "ruler_enumo": ("ruler", "enumo"),
        "eggmind": ("eggmind",),
    }
    found: dict[str, list[str]] = {}
    for control, terms in needles.items():
        matches = []
        for path in ROOT.iterdir():
            lowered = path.name.lower()
            if any(term in lowered for term in terms):
                matches.append(path.name)
        found[control] = sorted(matches)
    return found


def run() -> None:
    verify()
    phase2 = json.loads((RESULTS / "phase2.json").read_text(encoding="utf-8"))
    if phase2["version"] != "FOUNDRY_PHASE2_V1":
        raise RuntimeError("phase2 result contract mismatch")
    meter = selftest(sys.executable)
    upstream = _find_upstream_implementations()
    controls_ready = all(upstream.values())
    corpus = json.loads((RESULTS / "corpus_manifest.json").read_text(encoding="utf-8"))
    source_classes = sorted({row["source_class"] for row in corpus["records"]})
    external_corpus_ready = any("external" in item for item in source_classes)
    payload = {
        "version": "FOUNDRY_REMEDIATION_V1",
        "status": "EXECUTED_VALID_NEGATIVE",
        "freeze_sha256": file_sha256_bytes((RESULTS / "protocol_freeze.txt").read_bytes()),
        "phase2_sha256": file_sha256_bytes((RESULTS / "phase2.json").read_bytes()),
        "actions": {
            "resource_meter_hostile_component_test": meter,
            "upstream_control_checkout_audit": upstream,
            "corpus_source_class_audit": source_classes,
            "compiler_ir_dedup_backend_audit": {
                "available": False,
                "reason": "Foundry-1 calibration tools target byte artifacts; no typed tensor compiler lowering/dedup backend is integrated.",
            },
        },
        "prerequisite_progress": {
            "P1_external_control_conformance": controls_ready,
            "P2_independent_corpus_and_invocation_trace": external_corpus_ready,
            "P3_complete_resource_meter": False,
            "P3_component_selftest": meter["pass"],
            "P4_independent_typed_tool_verifier": True,
            "P5_native_compiler_deduplication": False,
            "P6_unchanged_prospective_freeze": True,
        },
        "next_repairs": [
            "vendor and reproduce upstream control implementations with paper-derived fixtures",
            "pin licensed external tensor/compiler projects and an independent invocation trace",
            "wrap every candidate, control, compiler, verifier, and failed child in one process-tree meter",
            "lower candidate tensor tools and compiler-native alternatives to canonical IR for deduplication",
        ],
    }
    (RESULTS / "phase3_remediation.json").write_text(
        canonical_json(payload) + "\n", encoding="utf-8"
    )
    print(
        "FOUNDRY_REMEDIATION_EXECUTED"
        f" meter_component={'PASS' if meter['pass'] else 'FAIL'}"
        f" controls_ready={str(controls_ready).lower()}"
        f" external_corpus_ready={str(external_corpus_ready).lower()}"
        " native_dedup_ready=false"
    )


if __name__ == "__main__":
    run()

