#!/usr/bin/env python3
"""Independently invoke and verify the evaluator-isolated Operator v5 candidate."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import subprocess
import sys
from typing import Any

from ghost_operator_core_v5 import (
    canonical_json,
    file_sha256,
    load_artifact,
    load_plan_text,
    measure_plan,
    sha256_json,
)
from ghost_operator_development_v5 import load_manifest
from ghost_operator_synthesis_v5 import enumerate_plans, structural_signature


def tree_choice(tree: dict[str, Any], features: dict[str, int]) -> int:
    while tree["kind"] == "branch":
        tree = tree["left"] if features[tree["feature"]] <= tree["threshold"] else tree["right"]
    return int(tree["plan_index"])


def verify(
    manifest: pathlib.Path,
    grammar_path: pathlib.Path,
    receipt_path: pathlib.Path,
    phase: str,
) -> None:
    candidate = pathlib.Path(__file__).with_name("ghost_operator_candidate_v5.py")
    grammar = json.loads(grammar_path.read_text(encoding="utf-8"))
    rows: list[dict[str, object]] = []
    maximum_error = 0.0
    for artifact_path in load_manifest(manifest, phase):
        artifact, raw = load_artifact(artifact_path)
        completed = subprocess.run(
            [sys.executable, str(candidate), str(artifact_path), str(grammar_path)],
            text=True,
            capture_output=True,
            timeout=30,
            check=False,
            env={"PATH": "/usr/bin:/bin", "PYTHONHASHSEED": "0"},
        )
        if completed.returncode:
            raise ValueError(
                f"candidate failed on {artifact.opaque_id}: {completed.stderr[-1000:]}"
            )
        candidate_text = completed.stdout.strip()
        selected = load_plan_text(candidate_text, artifact)
        signature = hashlib.sha256(structural_signature(artifact).encode()).hexdigest()
        tree = grammar["rules"].get(signature, {"kind": "leaf", "plan_index": 0})
        expected_index = tree_choice(tree, artifact.public_features())
        choices = enumerate_plans(artifact)
        if not 0 <= expected_index < len(choices):
            expected_index = 0
        expected = choices[expected_index]
        byte_identical = canonical_json(selected) == canonical_json(expected)
        if not byte_identical:
            raise ValueError(f"candidate plan drift on {artifact.opaque_id}")
        metrics = measure_plan(
            artifact,
            selected,
            backend="eager",
            repetitions=3,
            inner_iterations=2,
        )
        maximum_error = max(maximum_error, float(metrics["max_abs_error"]))
        if metrics["max_abs_error"] > 1.0e-5 or not metrics["layouts_valid"]:
            raise ValueError(f"candidate numerical replay failed on {artifact.opaque_id}")
        rows.append(
            {
                "status": "GHOST_OPERATOR_CANDIDATE_REPLAY_V5",
                "opaque_id": artifact.opaque_id,
                "artifact_sha256": hashlib.sha256(raw).hexdigest(),
                "structural_signature_sha256": signature,
                "selected_plan_index": expected_index,
                "selected_plan_sha256": sha256_json(selected),
                "byte_identical_to_evaluator_plan": byte_identical,
                "max_abs_error": metrics["max_abs_error"],
                "layouts_valid": metrics["layouts_valid"],
                "candidate_stderr": completed.stderr,
            }
        )
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    receipt_path.write_text(
        "\n".join(canonical_json(row) for row in rows) + "\n", encoding="utf-8"
    )
    print(
        "GHOST_OPERATOR_CANDIDATE_VERIFY_V5 PASS"
        f" artifacts={len(rows)} byte_identical={len(rows)}"
        f" phase={phase}"
        f" max_abs_error={maximum_error:.9g}"
        f" candidate_sha256={file_sha256(candidate)}"
        f" grammar_sha256={file_sha256(grammar_path)}"
        f" receipt_sha256={file_sha256(receipt_path)}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=pathlib.Path)
    parser.add_argument("grammar", type=pathlib.Path)
    parser.add_argument("receipt", type=pathlib.Path)
    parser.add_argument(
        "--phase",
        choices=(
            "DEVELOPMENT",
            "VALIDATION",
            "CONFIRMATION",
            "PREFREEZE",
            "HELDOUT",
        ),
        default="DEVELOPMENT",
    )
    args = parser.parse_args()
    verify(args.manifest, args.grammar, args.receipt, args.phase)


if __name__ == "__main__":
    main()
