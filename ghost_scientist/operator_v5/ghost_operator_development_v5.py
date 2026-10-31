#!/usr/bin/env python3
"""Isolated development measurement and multi-objective scoring for Operator v5."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import pathlib
import subprocess
import sys
import tempfile
from collections.abc import Sequence
from typing import Any

from ghost_operator_core_v5 import canonical_json, file_sha256, load_artifact
from ghost_operator_synthesis_v5 import enumerate_plans, structural_signature


OUTCOME_STATUS = "GHOST_OPERATOR_DEVELOPMENT_OUTCOME_V5"
SCORE_VERSION = "GHOST_OPERATOR_MULTI_OBJECTIVE_SCORE_V5_DEV1"
ABSOLUTE_TOLERANCE = 1.0e-5


def load_manifest(path: pathlib.Path, required_phase: str) -> list[pathlib.Path]:
    lines = path.read_text(encoding="utf-8").splitlines()
    expected = (
        "opaque_id\tphase\tartifact_path\tartifact_sha256\tfamily\tprovenance_sha256"
    )
    if not lines or lines[0] != expected:
        raise ValueError("manifest header mismatch")
    result: list[pathlib.Path] = []
    seen: set[str] = set()
    for number, line in enumerate(lines[1:], 2):
        fields = line.split("\t")
        if len(fields) != 6:
            raise ValueError(f"manifest line {number} field count mismatch")
        opaque_id, phase, artifact_text, expected_sha, _family, _provenance = fields
        if phase != required_phase or opaque_id in seen:
            raise ValueError(f"manifest line {number} phase/id violation")
        seen.add(opaque_id)
        artifact_path = pathlib.Path(artifact_text)
        if not artifact_path.is_absolute():
            if artifact_path.exists():
                artifact_path = artifact_path.resolve()
            else:
                artifact_path = (path.parent / artifact_path).resolve()
        if file_sha256(artifact_path) != expected_sha:
            raise ValueError(f"manifest line {number} artifact digest mismatch")
        artifact, _raw = load_artifact(artifact_path)
        if artifact.opaque_id != opaque_id:
            raise ValueError(f"manifest line {number} opaque id mismatch")
        result.append(artifact_path)
    if not result:
        raise ValueError("manifest is empty")
    return result


def measure_isolated(
    evaluator: pathlib.Path,
    artifact_path: pathlib.Path,
    plan_index: int,
    *,
    backend: str,
    repetitions: int,
    inner_iterations: int | None,
) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="ghost-operator-inductor-") as directory:
        root = pathlib.Path(directory)
        env = dict(os.environ)
        env.update(
            {
                "PYTHONPATH": str(evaluator.parent),
                "TORCHINDUCTOR_CACHE_DIR": str(root / "inductor"),
                "TRITON_CACHE_DIR": str(root / "triton"),
                "CUDA_VISIBLE_DEVICES": "",
                "OMP_NUM_THREADS": "1",
                "MKL_NUM_THREADS": "1",
            }
        )
        command = [
            sys.executable,
            str(evaluator),
            "measure",
            str(artifact_path),
            "evaluator_index",
            "--plan-index",
            str(plan_index),
            "--backend",
            backend,
            "--repetitions",
            str(repetitions),
        ]
        if inner_iterations is not None:
            command.extend(["--inner-iterations", str(inner_iterations)])
        completed = subprocess.run(
            command,
            env=env,
            text=True,
            capture_output=True,
            timeout=600,
            check=False,
        )
    if completed.returncode:
        return {
            "status": "MEASUREMENT_FAILED",
            "returncode": completed.returncode,
            "stderr": completed.stderr[-4000:],
            "stdout": completed.stdout[-4000:],
        }
    lines = [line for line in completed.stdout.splitlines() if line.startswith("{")]
    if len(lines) != 1:
        return {
            "status": "MEASUREMENT_FAILED",
            "returncode": completed.returncode,
            "stderr": completed.stderr[-4000:],
            "stdout": completed.stdout[-4000:],
            "reason": "evaluator did not emit exactly one JSON result",
        }
    payload = json.loads(lines[0])
    if payload.get("status") != "GHOST_OPERATOR_MEASURE_V5":
        raise ValueError("evaluator measure status mismatch")
    return {"status": "MEASURED", "receipt": payload, "stderr": completed.stderr[-2000:]}


def _geometric_mean(values: Sequence[float]) -> float:
    if not values or any(value <= 0.0 or not math.isfinite(value) for value in values):
        raise ValueError("geometric mean inputs are invalid")
    return math.exp(sum(math.log(value) for value in values) / len(values))


def score_artifact(rows: list[dict[str, Any]]) -> None:
    valid = [
        row
        for row in rows
        if row["measurement_status"] == "MEASURED"
        and row["numerically_valid"]
    ]
    if not valid:
        return
    fields = (
        "setup_compile_us",
        "latency_us",
        "amortized_total_us",
        "peak_rss_kb",
    )
    minima = {
        field: min(max(float(row["objectives"][field]), 1.0e-9) for row in valid)
        for field in fields
    }
    for row in rows:
        if row not in valid:
            row["score"] = None
            row["objective_ratios"] = None
            continue
        ratios = {
            field: max(float(row["objectives"][field]), 1.0e-9) / minima[field]
            for field in fields
        }
        row["objective_ratios"] = ratios
        row["score"] = _geometric_mean(tuple(ratios.values()))


def measure_manifest(
    manifest: pathlib.Path,
    output: pathlib.Path,
    *,
    backend: str,
    repetitions: int,
    inner_iterations: int | None,
    limit_artifacts: int | None,
    phase: str,
    start_artifact: int,
) -> None:
    evaluator = pathlib.Path(__file__).with_name("ghost_operator_evaluator_v5.py")
    artifact_paths = load_manifest(manifest, phase)
    artifact_paths = artifact_paths[start_artifact:]
    if limit_artifacts is not None:
        artifact_paths = artifact_paths[:limit_artifacts]
    all_rows: list[dict[str, Any]] = []
    for artifact_number, artifact_path in enumerate(artifact_paths, 1):
        artifact, raw = load_artifact(artifact_path)
        plans = enumerate_plans(artifact)
        artifact_rows: list[dict[str, Any]] = []
        for plan_index, plan in enumerate(plans):
            measured = measure_isolated(
                evaluator,
                artifact_path,
                plan_index,
                backend=backend,
                repetitions=repetitions,
                inner_iterations=inner_iterations,
            )
            row: dict[str, Any] = {
                "status": OUTCOME_STATUS,
                "score_version": SCORE_VERSION,
                "phase": phase,
                "opaque_id": artifact.opaque_id,
                "artifact_sha256": hashlib.sha256(raw).hexdigest(),
                "structural_signature_sha256": hashlib.sha256(
                    structural_signature(artifact).encode()
                ).hexdigest(),
                "features": artifact.public_features(),
                "plan_index": plan_index,
                "plan_sha256": hashlib.sha256(canonical_json(plan).encode()).hexdigest(),
                "measurement_status": measured["status"],
                "measurement_failure": None,
                "metrics": None,
                "numerically_valid": False,
                "objectives": None,
            }
            if measured["status"] == "MEASURED":
                metrics = measured["receipt"]["metrics"]
                row["metrics"] = metrics
                row["numerically_valid"] = (
                    float(metrics["max_abs_error"]) <= ABSOLUTE_TOLERANCE
                    and float(metrics["compiled_max_abs_error"]) <= ABSOLUTE_TOLERANCE
                    and bool(metrics["layouts_valid"])
                )
                row["objectives"] = {
                    "setup_compile_us": float(metrics["construction_us"])
                    + 1000.0 * float(metrics["compile_ms"]),
                    "latency_us": float(metrics["latency_us_median"]),
                    "amortized_total_us": float(metrics["amortized_total_us"]),
                    "peak_rss_kb": float(metrics["peak_rss_kb"]),
                    "static_peak_live_bytes": int(metrics["static_peak_live_bytes"]),
                    "derived_parameter_bytes": int(metrics["derived_parameter_bytes"]),
                }
            else:
                row["measurement_failure"] = measured
            artifact_rows.append(row)
            all_rows.append(row)
            print(
                "GHOST_OPERATOR_DEVELOPMENT_PROGRESS_V5"
                f" artifact={artifact.opaque_id}"
                f" artifact_index={artifact_number}_of_{len(artifact_paths)}"
                f" plan={plan_index + 1}_of_{len(plans)}"
                f" status={measured['status']}",
                flush=True,
            )
        score_artifact(artifact_rows)
        valid = sum(
            row["measurement_status"] == "MEASURED" and row["numerically_valid"]
            for row in artifact_rows
        )
        print(
            "GHOST_OPERATOR_DEVELOPMENT_ARTIFACT_V5"
            f" artifact={artifact.opaque_id} valid_plans={valid}_of_{len(plans)}",
            flush=True,
        )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        "\n".join(canonical_json(row) for row in all_rows) + "\n",
        encoding="utf-8",
    )
    failed = sum(row["measurement_status"] != "MEASURED" for row in all_rows)
    invalid = sum(
        row["measurement_status"] == "MEASURED" and not row["numerically_valid"]
        for row in all_rows
    )
    print(
        "GHOST_OPERATOR_DEVELOPMENT_V5 PASS"
        f" artifacts={len(artifact_paths)} outcomes={len(all_rows)}"
        f" phase={phase}"
        f" measurement_failures={failed} numerical_invalid={invalid}"
        f" score_version={SCORE_VERSION}"
        f" output_sha256={file_sha256(output)}",
        flush=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--backend", choices=("eager", "inductor"), default="inductor")
    parser.add_argument("--repetitions", type=int, default=7)
    parser.add_argument("--inner-iterations", type=int)
    parser.add_argument("--limit-artifacts", type=int)
    parser.add_argument("--start-artifact", type=int, default=0)
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
    measure_manifest(
        args.manifest,
        args.output,
        backend=args.backend,
        repetitions=args.repetitions,
        inner_iterations=args.inner_iterations,
        limit_artifacts=args.limit_artifacts,
        phase=args.phase,
        start_artifact=args.start_artifact,
    )


if __name__ == "__main__":
    main()
