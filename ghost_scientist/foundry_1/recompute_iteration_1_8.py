#!/usr/bin/env python3
"""Recompute readiness after external application trace and reachability audit."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_external_application_intake import verify as verify_external
from freeze_tensor_forge_component import verify as verify_tensor


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def load(name: str, version: str) -> tuple[dict, str]:
    raw = (RESULTS / name).read_bytes()
    value = json.loads(raw)
    if value["version"] != version:
        raise RuntimeError(f"{name} version mismatch")
    return value, hashlib.sha256(raw).hexdigest()


def run() -> None:
    verify_external()
    verify_tensor()
    prior, prior_sha = load(
        "readiness_iteration_1_7.json", "FOUNDRY_READINESS_ITERATION_1_7"
    )
    trace, trace_sha = load(
        "phase15_external_application_trace.json",
        "FOUNDRY_EXTERNAL_APPLICATION_TRACE_V1",
    )
    reachability, reachability_sha = load(
        "phase16_external_tool_reachability.json",
        "FOUNDRY_EXTERNAL_TOOL_REACHABILITY_V1",
    )
    if (
        trace["status"] != "EXTERNAL_APPLICATION_TRACE_COMPONENT_READY"
        or reachability["status"] != "EXTERNAL_TOOL_REACHABILITY_VALID_NEGATIVE"
        or reachability["coarse_reachable_pairs"] != 0
    ):
        raise RuntimeError("external application evidence is not the expected result")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_1_8",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": prior_sha,
        "external_trace_sha256": trace_sha,
        "reachability_sha256": reachability_sha,
        "progress": {
            "P2_external_application_sources": True,
            "P2_runtime_invocation_trace": True,
            "P2_compiler_graphs": True,
            "P2_families": trace["summary"]["families"],
            "P2_recorded_invocations": trace["summary"]["total_invocations"],
            "P2_tool_reachable_pairs": 0,
            "P2_complete": False,
        },
        "interpretation": (
            "Four pinned upstream applications now provide real runtime traces "
            "and exported compiler graphs. None can exercise a frozen forged "
            "tool, so the intake is valid external-corpus evidence but not a "
            "valid tool-reuse trial corpus."
        ),
        "remediation": {
            "required": True,
            "next_action": (
                "use the observed external applications as calibration only; "
                "either forge ATen-domain tools from them and reserve new "
                "upstream applications, or pre-freeze a new external intake "
                "whose semantics overlap the frozen tools"
            ),
            "forbidden_shortcut": (
                "do not relabel zero-reachability heterogeneity as a P2 pass"
            ),
        },
        "remaining_blockers": prior["remaining_blockers"],
    }
    (RESULTS / "readiness_iteration_1_8.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_1_8_NOT_READY"
        f" external_families={trace['summary']['families']}"
        f" invocations={trace['summary']['total_invocations']}"
        " reachable=0 p2_complete=false"
    )


if __name__ == "__main__":
    run()
