#!/usr/bin/env python3
"""Recompute readiness after EggMind sufficiency and ISAMORE ingress phases."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_22.json"
    eggmind_path = (
        RESULTS / "eggmind_reproduction_sufficiency_result_v1_freeze.json"
    )
    ingress_path = (
        RESULTS / "isamore_exact_artifact_ingress_result_v1_freeze.json"
    )
    prior = json.loads(prior_path.read_text())
    eggmind = json.loads(eggmind_path.read_text())
    ingress = json.loads(ingress_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and prior["authorization"]["prerequisites_passed"] == 5
        and eggmind["status"]
        == "EGGMIND_PAPER_ONLY_FULL_REPRODUCTION_NOT_SPECIFIED"
        and eggmind["A8_production_integrated"] is False
        and ingress["status"]
        == "ISAMORE_EXACT_ARTIFACT_INGRESS_CONFORMANCE_PASS"
        and ingress["real_exact_artifacts_acquired"] == 0
        and ingress["P1_complete"] is False
    ):
        raise RuntimeError("iteration 5.23 inputs changed")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_23",
        "prior_sha256": sha(prior_path),
        "eggmind_sufficiency_freeze_sha256": sha(eggmind_path),
        "isamore_ingress_freeze_sha256": sha(ingress_path),
        "prerequisites": prior["prerequisites"],
        "progress": {
            **prior["progress"],
            "A8_paper_specified_surfaces": 10,
            "A8_missing_outcome_determining_surfaces": 16,
            "A8_paper_only_full_reproduction_specified": False,
            "A8_llm_free_substitute_requires_new_control_label": True,
            "isamore_exact_ingress_locked_identities": 310,
            "isamore_exact_ingress_hostile_rejections": 11,
            "isamore_exact_ingress_conformance_passed": True,
            "isamore_exact_ingress_real_artifacts_acquired": 0,
        },
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "The defining EggMind paper publishes a substantive architecture "
            "but leaves 16 outcome-determining policy, proof-extraction, "
            "lowering, cache, and fixture surfaces unspecified, while no "
            "official executable source revision is discoverable. A paper-only "
            "or LLM-free reconstruction therefore cannot be promoted as "
            "source-faithful EggMind or A8. The next phase removes manual "
            "artifact decisions from the still-shortest A6 route: an exact "
            "Cargo.lock ingress gate recognizes 310 registry identities, "
            "atomically stages valid archives, and rejects 11 hostile archive "
            "classes. Its real inbox is empty, so no source was acquired and "
            "readiness does not advance."
        ),
        "remaining_blockers": prior["remaining_blockers"],
        "remediation": {
            "required": True,
            "next_action": (
                "keep validation-v6 sealed; feed externally transported exact "
                "name-version.crate archives to the frozen ingress gate, then "
                "resume the unchanged ISAMORE offline build once the locked "
                "closure, native Coin-OR CBC, and pinned nightly are present"
            ),
            "forbidden_shortcuts": [
                "do not call the partial EqSatL boundary EggMind or A8",
                "do not replace EggMind's missing LLM policy with a deterministic policy under the same source-faithful label",
                "do not treat docs.rs visibility or a 5.2.1 Git manifest as the exact 5.2.4 archive",
                "do not bypass Cargo.lock checksums or archive path safety",
                "do not count ingress conformance as source acquisition or P1 progress",
                "do not open validation-v6 before full authorization",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_23.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_23"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " controls=3/4 integrated=6/10"
        " A8=false ingress_exact=0 prospective=false"
    )


if __name__ == "__main__":
    main()
