#!/usr/bin/env python3
"""Recompute readiness after archive recovery and A1 no-go phases."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_19.json"
    freeze_path = RESULTS / "foundry_remediation_v20_freeze.json"
    prior = json.loads(prior_path.read_text())
    freeze = json.loads(freeze_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and freeze["phases"] == [130, 131]
        and freeze["exact_archives_acquired"] == 0
        and freeze["A1_opaque_fallback_rejected"] is True
        and freeze["production_integrated_arms"] == 6
    ):
        raise RuntimeError("iteration 5.20 inputs changed")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_20",
        "prior_sha256": sha(prior_path),
        "foundry_remediation_freeze_sha256": sha(freeze_path),
        "prerequisites": prior["prerequisites"],
        "progress": {
            **prior["progress"],
            "isamore_exact_archive_transport_probes": 4,
            "isamore_exact_archives_acquired": 0,
            "isamore_substitute_source_accepted": False,
            "A1_opaque_reference_fallback_rejected": True,
            "A1_opaque_hostile_probes_rejected": 1,
            "A1_production_integrated": False,
        },
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "Four exact immutable Kiddo-family archive transfers were attempted "
            "under bounded timeouts but yielded no checksum-matching bytes. A "
            "separate semantic audit proves that arbitrary framework execution "
            "cannot be hidden inside frozen A1's reference plan: the reference "
            "program is strict Operator-v5 IR and rejects an opaque call."
        ),
        "remaining_blockers": prior["remaining_blockers"],
        "remediation": {
            "required": True,
            "next_action": (
                "keep A6 as the shortest source-faithful path when transport "
                "returns; while transport is closed, prefreeze a separately "
                "named Enumo tensor-domain feasibility phase without promoting "
                "the Boolean A7 control"
            ),
            "forbidden_shortcuts": [
                "do not relabel the checked-in Kiddo 5.2.1 manifest as 5.2.4",
                "do not wrap arbitrary framework execution as an A1 reference plan",
                "do not rename a new tensor SynthLanguage as the frozen Boolean A7",
                "do not open validation-v6 before authorization",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_20.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_20"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " controls=3/4 integrated=6/10 exact_archives=0/4"
        " A1_opaque_fallback=false prospective=false"
    )


if __name__ == "__main__":
    main()
