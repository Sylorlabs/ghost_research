#!/usr/bin/env python3
"""Recompute readiness after the tensor-forge component freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_tensor_forge_component import MANIFEST, verify


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def run() -> None:
    freeze = verify()
    prior_path = RESULTS / "readiness_iteration_1_6.json"
    prior_raw = prior_path.read_bytes()
    prior = json.loads(prior_raw)
    if prior["version"] != "FOUNDRY_READINESS_ITERATION_1_6":
        raise RuntimeError("iteration 1.6 version mismatch")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_1_7",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": hashlib.sha256(prior_raw).hexdigest(),
        "component_freeze_file_sha256": hashlib.sha256(MANIFEST.read_bytes()).hexdigest(),
        "component_records_sha256": freeze["records_sha256"],
        "progress": {
            "P6_tensor_forge_component_frozen": True,
            "P6_full_protocol_frozen": False,
            "prospective_trial_authorized": False,
        },
        "remaining_blockers": prior["remaining_blockers"],
        "interpretation": (
            "The tensor forge, independent evaluation, native classification, "
            "resource receipts, admission policy, and readiness evidence are "
            "now immutable inputs to subsequent external work. The full v6 "
            "protocol cannot freeze until P1-P5 inputs are complete."
        ),
    }
    (RESULTS / "readiness_iteration_1_7.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_1_7_NOT_READY"
        f" component_records={len(freeze['records'])}"
        " p6_component=true p6_full=false"
    )


if __name__ == "__main__":
    run()
