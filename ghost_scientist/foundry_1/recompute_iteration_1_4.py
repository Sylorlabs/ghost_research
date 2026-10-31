#!/usr/bin/env python3
"""Recompute Foundry-1.4 after process-tree metering integration."""

from __future__ import annotations

import json
import pathlib

from independent_evaluator import canonical_json, file_sha256_bytes


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_1_3.json"
    audit_path = RESULTS / "phase8_resource_audit.json"
    prior = json.loads(prior_path.read_text(encoding="utf-8"))
    audit = json.loads(audit_path.read_text(encoding="utf-8"))
    if prior["verdict"] != "FOUNDRY_V6_NOT_READY":
        raise RuntimeError("prior iteration did not fail closed")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_1_4",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": file_sha256_bytes(prior_path.read_bytes()),
        "resource_audit_sha256": file_sha256_bytes(audit_path.read_bytes()),
        "progress": {
            "P3_process_tree_meter_selftest": audit["meter_selftest"]["pass"],
            "P3_representative_local_arms": audit["P3"][
                "representative_local_arms_integrated"
            ],
            "P3_external_controls": False,
            "P3_complete": audit["P3"]["complete"],
        },
        "remaining_blockers": prior["remaining_blockers"],
        "interpretation": (
            "Process-group accounting now charges representative forge, fixed, verifier, "
            "compiler, and external-corpus subprocess trees, including failure and timeout "
            "attacks. P3 remains incomplete until every external and prospective arm uses it."
        ),
    }
    (RESULTS / "readiness_iteration_1_4.json").write_text(
        canonical_json(payload) + "\n", encoding="utf-8"
    )
    print(
        "FOUNDRY_1_4_NOT_READY"
        f" local_meter={'PASS' if audit['P3']['representative_local_arms_integrated'] else 'FAIL'}"
        " external_controls=false"
    )


if __name__ == "__main__":
    main()

