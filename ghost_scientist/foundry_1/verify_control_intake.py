#!/usr/bin/env python3
"""Verify the external control intake without inflating it to reproduction."""

from __future__ import annotations

import json
import pathlib
import re

from independent_evaluator import canonical_json, file_sha256_bytes


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def main() -> None:
    path = HERE / "CONTROL_INTAKE.json"
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload["schema"] != "foundry-external-control-intake-v1":
        raise RuntimeError("control intake schema mismatch")
    controls = payload["controls"]
    if [item["id"] for item in controls] != [
        "stitch",
        "babble_isamore",
        "ruler_enumo",
        "eggmind",
    ]:
        raise RuntimeError("critical external control coverage mismatch")
    pinned = 0
    reproduced = 0
    for item in controls:
        if not item["defining_fixture"]:
            raise RuntimeError(f"{item['id']} lacks a defining fixture")
        revision = item.get("revision")
        blob = item.get("readme_blob_sha")
        if revision and (re.fullmatch(r"[0-9a-f]{40}", revision) or revision == "popl23") and re.fullmatch(r"[0-9a-f]{40}", blob or ""):
            pinned += 1
        reproduced += int(item["conformance_executed"] is True)
        if item["conformance_executed"] and not item["source_checkout_available"]:
            raise RuntimeError("conformance cannot pass without a source checkout")
    result = {
        "version": "FOUNDRY_CONTROL_INTAKE_VERIFY_V1",
        "status": "CONTROL_SOURCE_INTAKE_PARTIAL",
        "intake_sha256": file_sha256_bytes(path.read_bytes()),
        "critical_controls": len(controls),
        "repository_records_pinned": pinned,
        "conformance_executed": reproduced,
        "P1_source_intake_component": pinned >= 3,
        "P1_complete": reproduced == len(controls),
        "blocking_fact": (
            "Shell Git transport is unavailable and EggMind source was not located; "
            "repository metadata is not an executable reproduction."
        ),
    }
    RESULTS.mkdir(parents=True, exist_ok=True)
    (RESULTS / "phase7_control_intake.json").write_text(
        canonical_json(result) + "\n", encoding="utf-8"
    )
    print(
        "FOUNDRY_PHASE7_CONTROL_INTAKE_PARTIAL"
        f" pinned={pinned}/{len(controls)} reproduced={reproduced}/{len(controls)}"
        " p1_complete=false"
    )


if __name__ == "__main__":
    main()

