#!/usr/bin/env python3
"""Build the strong non-conditional fixed-portfolio control for Operator v5."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import pathlib
from collections import defaultdict
from typing import Any

from ghost_operator_core_v5 import canonical_json, file_sha256, load_artifact
from ghost_operator_development_v5 import load_manifest
from ghost_operator_learn_v5 import load_outcomes
from ghost_operator_synthesis_v5 import structural_signature


def build(
    development_manifest: pathlib.Path,
    development_outcomes: pathlib.Path,
    validation_manifest: pathlib.Path,
    validation_outcomes: pathlib.Path,
    output: pathlib.Path,
) -> None:
    artifacts: dict[str, tuple[Any, bytes]] = {}
    for path in load_manifest(development_manifest, "DEVELOPMENT"):
        artifact, raw = load_artifact(path)
        artifacts[artifact.opaque_id] = (artifact, raw)
    outcomes = load_outcomes(development_outcomes, artifacts)
    validation_artifacts: dict[str, tuple[Any, bytes]] = {}
    for path in load_manifest(validation_manifest, "VALIDATION"):
        artifact, raw = load_artifact(path)
        validation_artifacts[artifact.opaque_id] = (artifact, raw)
    validation_rows = load_outcomes(validation_outcomes, validation_artifacts)
    artifacts.update(validation_artifacts)
    outcomes.update(validation_rows)

    groups: dict[str, list[str]] = defaultdict(list)
    for opaque_id, (artifact, _raw) in artifacts.items():
        signature = hashlib.sha256(structural_signature(artifact).encode()).hexdigest()
        groups[signature].append(opaque_id)
    rules: dict[str, int] = {}
    receipts = []
    replay_examples = []
    for signature, ids in sorted(groups.items()):
        count = len(outcomes[ids[0]])
        scored = []
        for index in range(count):
            log_score = sum(
                math.log(float(outcomes[opaque_id][index]["score"]))
                for opaque_id in ids
            )
            scored.append((log_score, index))
        log_score, index = min(scored)
        rules[signature] = index
        receipts.append(
            {
                "structural_signature_sha256": signature,
                "artifact_count": len(ids),
                "fixed_plan_index": index,
                "geometric_training_score": math.exp(log_score / len(ids)),
            }
        )
        for opaque_id in sorted(ids):
            artifact = artifacts[opaque_id][0]
            oracle = min(
                outcomes[opaque_id],
                key=lambda plan_index: outcomes[opaque_id][plan_index]["score"],
            )
            replay_examples.append(
                {
                    "opaque_id": opaque_id,
                    "structural_signature_sha256": signature,
                    "features": artifact.public_features(),
                    "oracle_plan_index": oracle,
                }
            )
    payload = {
        "version": "GHOST_OPERATOR_FIXED_PORTFOLIO_V5",
        "status": "CALIBRATED_NOT_FROZEN",
        "development_manifest_sha256": file_sha256(development_manifest),
        "development_outcomes_sha256": file_sha256(development_outcomes),
        "validation_manifest_sha256": file_sha256(validation_manifest),
        "validation_outcomes_sha256": file_sha256(validation_outcomes),
        "conditional_features": False,
        "rules": rules,
        "receipts": receipts,
        "replay_examples": replay_examples,
    }
    output.write_text(canonical_json(payload) + "\n", encoding="utf-8")
    print(
        "GHOST_OPERATOR_FIXED_PORTFOLIO_V5 PASS"
        f" signatures={len(rules)} artifacts={len(artifacts)}"
        f" conditional_features=false output_sha256={file_sha256(output)}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("development_manifest", type=pathlib.Path)
    parser.add_argument("development_outcomes", type=pathlib.Path)
    parser.add_argument("validation_manifest", type=pathlib.Path)
    parser.add_argument("validation_outcomes", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()
    build(
        args.development_manifest,
        args.development_outcomes,
        args.validation_manifest,
        args.validation_outcomes,
        args.output,
    )


if __name__ == "__main__":
    main()
