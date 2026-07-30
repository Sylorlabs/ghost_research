#!/usr/bin/env python3
"""Independent structural and numerical verifier for Tensor v4 plans.

This file imports none of the candidate, constructor, evaluator, extractor, or
shared tensor core.  It proves that the plan is an exact partition of the
original projections and independently checks packed-vs-separate linear
semantics with NumPy across dtypes and seeds.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys
from collections.abc import Iterable, Sequence
from typing import Any

import numpy as np


ARTIFACT_VERSION = "GHOST_TENSOR_ARTIFACT_V4"
PLAN_VERSION = "GHOST_TENSOR_PLAN_V4"
STATUS = "GHOST_TENSOR_CANDIDATE_V4"


class VerificationError(ValueError):
    pass


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def strict_json(raw: bytes) -> dict[str, Any]:
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise VerificationError("invalid JSON") from exc
    if not isinstance(value, dict):
        raise VerificationError("object required")
    return value


def artifact_contract(payload: dict[str, Any]) -> tuple[list[int], list[dict[str, Any]], int]:
    if set(payload) != {
        "version",
        "opaque_id",
        "input",
        "projections",
        "weight_seed_hex",
        "output_contract",
    } or payload.get("version") != ARTIFACT_VERSION:
        raise VerificationError("artifact contract mismatch")
    input_spec = payload["input"]
    if set(input_spec) != {"shape", "dtype", "layout"}:
        raise VerificationError("input contract mismatch")
    shape = input_spec["shape"]
    if (
        not isinstance(shape, list)
        or len(shape) != 3
        or any(type(value) is not int or value <= 0 for value in shape)
        or input_spec["dtype"] not in ("float32", "float64")
        or input_spec["layout"] != "contiguous"
        or payload["output_contract"] != "BHTD_last_dim_stride_1"
    ):
        raise VerificationError("invalid input type")
    projections = payload["projections"]
    if not isinstance(projections, list) or not (2 <= len(projections) <= 6):
        raise VerificationError("invalid projection count")
    bias_values: list[bool] = []
    for index, projection in enumerate(projections):
        if set(projection) != {"opaque_parameter", "out_features", "heads", "bias"}:
            raise VerificationError("projection contract mismatch")
        if (
            projection["opaque_parameter"] != f"p{index}"
            or type(projection["out_features"]) is not int
            or type(projection["heads"]) is not int
            or projection["out_features"] <= 0
            or projection["heads"] <= 0
            or projection["out_features"] % projection["heads"]
            or type(projection["bias"]) is not bool
        ):
            raise VerificationError("invalid projection type")
        bias_values.append(projection["bias"])
    if len(set(bias_values)) != 1:
        raise VerificationError("mixed bias cluster")
    try:
        weight_seed = int(payload["weight_seed_hex"].removeprefix("0x"), 16)
    except (AttributeError, ValueError) as exc:
        raise VerificationError("invalid weight seed") from exc
    return shape, projections, weight_seed


def canonical_partition(groups: Iterable[Iterable[int]], count: int) -> list[list[int]]:
    try:
        result = sorted((sorted(group) for group in groups), key=lambda group: group[0])
    except (TypeError, IndexError) as exc:
        raise VerificationError("invalid plan groups") from exc
    flat = [index for group in result for index in group]
    if (
        any(not group for group in result)
        or any(type(index) is not int for index in flat)
        or sorted(flat) != list(range(count))
        or len(set(flat)) != count
    ):
        raise VerificationError("plan is not an exact partition")
    return result


def feature_digest(shape: list[int], projections: list[dict[str, Any]]) -> str:
    batch, sequence, width = shape
    outputs = [projection["out_features"] for projection in projections]
    features = {
        "batch": batch,
        "sequence": sequence,
        "tokens": batch * sequence,
        "in_features": width,
        "total_out": sum(outputs),
        "projection_count": len(projections),
        "work": batch * sequence * width * sum(outputs),
        "has_bias": int(any(projection["bias"] for projection in projections)),
        "heterogeneous_out": int(len(set(outputs)) > 1),
    }
    return hashlib.sha256(canonical_json(features).encode("utf-8")).hexdigest()


def numerical_checks(
    shape: list[int],
    projections: list[dict[str, Any]],
    groups: list[list[int]],
    weight_seed: int,
) -> tuple[float, float, float, int]:
    maximum_absolute = 0.0
    maximum_relative = 0.0
    maximum_forward_error_bound_ratio = 0.0
    cases = 0
    for dtype in (np.float32, np.float64):
        for case_seed in (0xA11CE, 0xBADC0DE, 0xC0FFEE, 0x51A7E):
            rng = np.random.default_rng(weight_seed ^ case_seed)
            tensor = rng.standard_normal(shape).astype(dtype)
            weights: list[np.ndarray] = []
            biases: list[np.ndarray | None] = []
            for projection in projections:
                output = projection["out_features"]
                weight = rng.standard_normal((output, shape[-1])).astype(dtype)
                bias = (
                    rng.standard_normal((output,)).astype(dtype)
                    if projection["bias"]
                    else None
                )
                weights.append(weight)
                biases.append(bias)
            reference = [
                tensor @ weight.T + (bias if bias is not None else dtype(0))
                for weight, bias in zip(weights, biases, strict=True)
            ]
            candidate: list[np.ndarray | None] = [None] * len(projections)
            for group in groups:
                packed_weight = np.concatenate([weights[index] for index in group], axis=0)
                if biases[group[0]] is None:
                    packed_bias = None
                else:
                    packed_bias = np.concatenate(
                        [biases[index] for index in group if biases[index] is not None],
                        axis=0,
                    )
                packed = tensor @ packed_weight.T
                if packed_bias is not None:
                    packed = packed + packed_bias
                offsets = np.cumsum(
                    [projections[index]["out_features"] for index in group]
                )[:-1]
                pieces = np.split(packed, offsets, axis=-1)
                for index, piece in zip(group, pieces, strict=True):
                    projection = projections[index]
                    reshaped = piece.reshape(
                        shape[0],
                        shape[1],
                        projection["heads"],
                        projection["out_features"] // projection["heads"],
                    ).transpose(0, 2, 1, 3)
                    if reshaped.strides[-1] != reshaped.itemsize:
                        raise VerificationError("last-dimension layout contract failed")
                    candidate[index] = reshaped
            for projection_index, (projection, expected_raw, actual) in enumerate(
                zip(projections, reference, candidate, strict=True)
            ):
                expected = expected_raw.reshape(
                    shape[0],
                    shape[1],
                    projection["heads"],
                    projection["out_features"] // projection["heads"],
                ).transpose(0, 2, 1, 3)
                if actual is None or actual.shape != expected.shape or actual.dtype != expected.dtype:
                    raise VerificationError("shape or dtype changed")
                difference = np.abs(expected - actual)
                maximum_absolute = max(maximum_absolute, float(difference.max(initial=0.0)))
                denominator = np.maximum(np.abs(expected), np.finfo(dtype).tiny)
                maximum_relative = max(
                    maximum_relative,
                    float((difference / denominator).max(initial=0.0)),
                )
                weight = weights[projection_index]
                bias = biases[projection_index]
                magnitude = np.abs(tensor) @ np.abs(weight).T
                if bias is not None:
                    magnitude = magnitude + np.abs(bias)
                magnitude = magnitude.reshape(
                    expected.shape[0],
                    expected.shape[2],
                    expected.shape[1],
                    expected.shape[3],
                ).transpose(0, 2, 1, 3)
                epsilon = np.finfo(dtype).eps
                reduction_terms = shape[-1] + int(bias is not None)
                gamma = (
                    reduction_terms
                    * epsilon
                    / (1.0 - reduction_terms * epsilon)
                )
                # Separate and packed GEMMs may select different legal
                # accumulation orders.  Four gamma_n terms conservatively
                # cover the forward error of both evaluations plus bias.
                forward_bound = (
                    4.0 * gamma * magnitude + np.finfo(dtype).tiny
                )
                bound_ratio = difference / forward_bound
                maximum_forward_error_bound_ratio = max(
                    maximum_forward_error_bound_ratio,
                    float(bound_ratio.max(initial=0.0)),
                )
            cases += 1
    if maximum_forward_error_bound_ratio > 1.0:
        raise VerificationError(
            "independent numerical equivalence exceeded forward-error bound"
        )
    return (
        maximum_absolute,
        maximum_relative,
        maximum_forward_error_bound_ratio,
        cases,
    )


def verify(
    artifact_raw: bytes,
    candidate_raw: bytes,
    expected_grammar_sha: str,
) -> dict[str, object]:
    if candidate_raw.count(b"\n") > 1 or b"\r" in candidate_raw:
        raise VerificationError("candidate emitted extra records")
    artifact = strict_json(artifact_raw)
    candidate = strict_json(candidate_raw)
    shape, projections, weight_seed = artifact_contract(artifact)
    if set(candidate) != {
        "status",
        "artifact_sha256",
        "grammar_sha256",
        "features_sha256",
        "plan",
        "final_seccomp",
    } or candidate.get("status") != STATUS:
        raise VerificationError("candidate record contract mismatch")
    if candidate["artifact_sha256"] != hashlib.sha256(artifact_raw).hexdigest():
        raise VerificationError("artifact digest mismatch")
    if candidate["grammar_sha256"] != expected_grammar_sha:
        raise VerificationError("grammar digest mismatch")
    if candidate["features_sha256"] != feature_digest(shape, projections):
        raise VerificationError("feature digest mismatch")
    if candidate["final_seccomp"] is not True:
        raise VerificationError("candidate did not report final seccomp")
    plan = candidate["plan"]
    if (
        not isinstance(plan, dict)
        or set(plan) != {"version", "groups"}
        or plan["version"] != PLAN_VERSION
    ):
        raise VerificationError("plan contract mismatch")
    groups = canonical_partition(plan["groups"], len(projections))
    (
        maximum_absolute,
        maximum_relative,
        maximum_forward_error_bound_ratio,
        cases,
    ) = numerical_checks(
        shape, projections, groups, weight_seed
    )
    return {
        "status": "GHOST_TENSOR_VERIFY_V4_PASS",
        "structural_equivalence": True,
        "shape_contract": True,
        "dtype_contract": True,
        "layout_contract": True,
        "numerical_cases": cases,
        "max_abs_error": maximum_absolute,
        "max_rel_error": maximum_relative,
        "max_forward_error_bound_ratio": maximum_forward_error_bound_ratio,
        "plan_sha256": hashlib.sha256(
            canonical_json({"version": PLAN_VERSION, "groups": groups}).encode("utf-8")
        ).hexdigest(),
    }


def selftest() -> None:
    artifact = {
        "version": ARTIFACT_VERSION,
        "opaque_id": "verify_selftest",
        "input": {"shape": [1, 4, 16], "dtype": "float32", "layout": "contiguous"},
        "projections": [
            {
                "opaque_parameter": f"p{index}",
                "out_features": 16,
                "heads": 4,
                "bias": True,
            }
            for index in range(3)
        ],
        "weight_seed_hex": "0x12345678",
        "output_contract": "BHTD_last_dim_stride_1",
    }
    artifact_raw = (canonical_json(artifact) + "\n").encode("utf-8")
    grammar_sha = "a" * 64
    candidate = {
        "status": STATUS,
        "artifact_sha256": hashlib.sha256(artifact_raw).hexdigest(),
        "grammar_sha256": grammar_sha,
        "features_sha256": feature_digest(
            artifact["input"]["shape"], artifact["projections"]
        ),
        "plan": {"version": PLAN_VERSION, "groups": [[0, 1, 2]]},
        "final_seccomp": True,
    }
    candidate_raw = (canonical_json(candidate) + "\n").encode("utf-8")
    receipt = verify(artifact_raw, candidate_raw, grammar_sha)
    if receipt["numerical_cases"] != 8:
        raise AssertionError("numerical test count mismatch")
    mutations = (
        candidate_raw.replace(b"\"groups\":[[0,1,2]]", b"\"groups\":[[0,1]]"),
        candidate_raw.replace(grammar_sha.encode(), ("b" * 64).encode()),
        candidate_raw.replace(b"\"final_seccomp\":true", b"\"final_seccomp\":false"),
        candidate_raw.replace(
            candidate["features_sha256"].encode(), ("0" * 64).encode()
        ),
        candidate_raw + b"EXTRA\n",
    )
    rejected = 0
    for mutation in mutations:
        try:
            verify(artifact_raw, mutation, grammar_sha)
        except VerificationError:
            rejected += 1
    if rejected != len(mutations):
        raise AssertionError("mutation rejection failed")
    print(
        "GHOST_TENSOR_VERIFY_V4_SELFTEST PASS"
        f" mutations_rejected={rejected}_of_{len(mutations)}"
        " structural=true numerical_cases=8"
    )


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--artifact")
    parser.add_argument("--grammar-sha")
    args = parser.parse_args(argv)
    if args.selftest:
        selftest()
        return
    if not args.artifact or not args.grammar_sha:
        parser.error("--artifact and --grammar-sha are required")
    artifact_raw = pathlib.Path(args.artifact).read_bytes()
    candidate_raw = sys.stdin.buffer.read()
    try:
        receipt = verify(artifact_raw, candidate_raw, args.grammar_sha)
    except VerificationError as exc:
        print(f"GHOST_TENSOR_VERIFY_V4_REJECT {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
    print(canonical_json(receipt))


if __name__ == "__main__":
    main()
