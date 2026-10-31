#!/usr/bin/env python3
"""Recompute Foundry-1.5 after future-tool admission hardening."""

from __future__ import annotations

import json
import pathlib

from independent_evaluator import canonical_json, file_sha256_bytes


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_1_4.json"
    admission_path = RESULTS / "phase9_future_tool_admission.json"
    prior = json.loads(prior_path.read_text(encoding="utf-8"))
    admission = json.loads(admission_path.read_text(encoding="utf-8"))
    if prior["verdict"] != "FOUNDRY_V6_NOT_READY":
        raise RuntimeError("prior iteration did not fail closed")
    summary = admission["summary"]
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_1_5",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": file_sha256_bytes(prior_path.read_bytes()),
        "admission_sha256": file_sha256_bytes(admission_path.read_bytes()),
        "progress": {
            "P5_fail_closed_admission_policy": admission["P5"][
                "admission_policy_component"
            ],
            "P5_v5_1_seed_tools_admitted": admission["P5"][
                "v5_1_seed_tools_admitted"
            ],
            "P5_future_candidate_audit": False,
            "P5_complete": False,
        },
        "remaining_blockers": prior["remaining_blockers"],
        "interpretation": (
            f"The admission rule rejected {summary['REJECT_NATIVE_DUPLICATE']} "
            f"and quarantined {summary['QUARANTINE_UNRESOLVED']} v5.1 plans; "
            "zero are promoted into a future Foundry library without stronger evidence."
        ),
    }
    (RESULTS / "readiness_iteration_1_5.json").write_text(
        canonical_json(payload) + "\n", encoding="utf-8"
    )
    print(
        "FOUNDRY_1_5_NOT_READY"
        f" admitted={admission['P5']['v5_1_seed_tools_admitted']}"
        " p5_policy=PASS p5_complete=false"
    )


if __name__ == "__main__":
    main()

