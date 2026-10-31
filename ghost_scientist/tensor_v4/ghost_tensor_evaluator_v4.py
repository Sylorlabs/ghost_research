#!/usr/bin/env python3
"""Evaluator CLI for Ghost Scientist Tensor v4."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
from collections.abc import Sequence

from ghost_tensor_core_v4 import (
    ContractError,
    canonical_json,
    identity_partition,
    load_artifact,
    load_plan_text,
    measure_plan,
    packed_partition,
    plan_payload,
    random_partition,
    set_partitions,
    sha256_json,
)


def emit(payload: object) -> None:
    print(canonical_json(payload))


def command_validate(args: argparse.Namespace) -> None:
    artifact, raw = load_artifact(pathlib.Path(args.artifact))
    emit(
        {
            "status": "GHOST_TENSOR_ARTIFACT_V4_VALID",
            "opaque_id": artifact.opaque_id,
            "artifact_sha256": __import__("hashlib").sha256(raw).hexdigest(),
            "features": artifact.features(),
            "partition_count": len(set_partitions(len(artifact.projections))),
        }
    )


def selected_partition(args: argparse.Namespace, artifact):
    count = len(artifact.projections)
    if args.method == "identity":
        return identity_partition(count), None
    if args.method in ("pack_all", "no_probe"):
        return packed_partition(count), None
    if args.method == "fixed_egraph":
        from ghost_tensor_egraph_v4 import saturate

        return saturate(count)
    if args.method == "random":
        return (
            random_partition(count, int(args.seed_hex.removeprefix("0x"), 16)),
            None,
        )
    if args.method == "plan":
        if args.plan_json is None:
            raise ContractError("--plan-json is required")
        return load_plan_text(args.plan_json, count), None
    raise ContractError(f"unknown method: {args.method}")


def command_measure(args: argparse.Namespace) -> None:
    artifact, raw = load_artifact(pathlib.Path(args.artifact))
    groups, method_receipt = selected_partition(args, artifact)
    metrics = measure_plan(
        artifact,
        groups,
        repetitions=args.repetitions,
        inner_iterations=args.inner_iterations,
        compile_backend=args.backend,
    )
    metrics["status"] = "GHOST_TENSOR_MEASURE_V4"
    metrics["opaque_id"] = artifact.opaque_id
    metrics["artifact_sha256"] = __import__("hashlib").sha256(raw).hexdigest()
    metrics["method"] = args.method
    if method_receipt is not None:
        metrics["equality_saturation_receipt"] = method_receipt
    emit(metrics)


def command_partitions(args: argparse.Namespace) -> None:
    artifact, _raw = load_artifact(pathlib.Path(args.artifact))
    payloads = [
        plan_payload(groups, len(artifact.projections))
        for groups in set_partitions(len(artifact.projections))
    ]
    emit(
        {
            "status": "GHOST_TENSOR_PARTITIONS_V4",
            "opaque_id": artifact.opaque_id,
            "partitions": payloads,
            "partitions_sha256": sha256_json(payloads),
        }
    )


def selftest() -> None:
    import tempfile

    artifact_payload = {
        "version": "GHOST_TENSOR_ARTIFACT_V4",
        "opaque_id": "selftest",
        "input": {
            "shape": [1, 4, 16],
            "dtype": "float32",
            "layout": "contiguous",
        },
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
    with tempfile.TemporaryDirectory(prefix="ghost-tensor-selftest-") as directory:
        path = pathlib.Path(directory) / "artifact.json"
        path.write_text(canonical_json(artifact_payload) + "\n", encoding="utf-8")
        artifact, _raw = load_artifact(path)
        partitions = set_partitions(3)
        if len(partitions) != 5:
            raise AssertionError("Bell(3) partition enumeration failed")
        for groups in partitions:
            loaded = load_plan_text(canonical_json(plan_payload(groups, 3)), 3)
            if loaded != groups:
                raise AssertionError("plan replay failed")
        identity = measure_plan(
            artifact,
            identity_partition(3),
            repetitions=3,
            inner_iterations=5,
            compile_backend="eager",
        )
        packed = measure_plan(
            artifact,
            packed_partition(3),
            repetitions=3,
            inner_iterations=5,
            compile_backend="eager",
        )
        if identity["logical_gemm_kernels"] != 3:
            raise AssertionError("identity kernel count is wrong")
        if packed["logical_gemm_kernels"] != 1:
            raise AssertionError("packed kernel count is wrong")
        if packed["max_abs_error"] > 1e-5:
            raise AssertionError("packed result changed semantics")
    print(
        "GHOST_TENSOR_EVALUATOR_V4_SELFTEST PASS"
        " partitions=5 shapes=true dtypes=true layouts=true numerical=true"
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate = subparsers.add_parser("validate")
    validate.add_argument("artifact")
    validate.set_defaults(function=command_validate)

    partitions = subparsers.add_parser("partitions")
    partitions.add_argument("artifact")
    partitions.set_defaults(function=command_partitions)

    measure = subparsers.add_parser("measure")
    measure.add_argument("artifact")
    measure.add_argument(
        "method",
        choices=("identity", "pack_all", "fixed_egraph", "no_probe", "random", "plan"),
    )
    measure.add_argument("--plan-json")
    measure.add_argument("--seed-hex", default="0x72616e646f6d")
    measure.add_argument("--backend", choices=("eager", "inductor"), default="inductor")
    measure.add_argument("--repetitions", type=int, default=9)
    measure.add_argument("--inner-iterations", type=int)
    measure.set_defaults(function=command_measure)

    test = subparsers.add_parser("selftest")
    test.set_defaults(function=lambda _args: selftest())
    return parser


def main(argv: Sequence[str] | None = None) -> None:
    args = build_parser().parse_args(argv)
    try:
        args.function(args)
    except ContractError as exc:
        print(f"GHOST_TENSOR_EVALUATOR_V4 REJECT {exc}", file=sys.stderr)
        raise SystemExit(1) from exc


if __name__ == "__main__":
    main()
