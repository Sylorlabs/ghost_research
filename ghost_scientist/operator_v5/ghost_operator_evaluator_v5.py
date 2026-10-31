#!/usr/bin/env python3
"""Evaluator CLI for Ghost Scientist Operator v5."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys
import tempfile
from collections.abc import Sequence

from ghost_operator_core_v5 import (
    ContractError,
    canonical_json,
    load_artifact,
    load_plan_text,
    measure_plan,
    reference_plan,
    sha256_json,
)
from ghost_operator_synthesis_v5 import enumerate_plans, structural_signature


def emit(payload: object) -> None:
    print(canonical_json(payload))


def command_validate(args: argparse.Namespace) -> None:
    artifact, raw = load_artifact(args.artifact)
    plans = enumerate_plans(artifact)
    emit(
        {
            "status": "GHOST_OPERATOR_ARTIFACT_V5_VALID",
            "opaque_id": artifact.opaque_id,
            "artifact_sha256": hashlib.sha256(raw).hexdigest(),
            "features": artifact.public_features(),
            "structural_signature_sha256": hashlib.sha256(
                structural_signature(artifact).encode()
            ).hexdigest(),
            "evaluator_plan_count": len(plans),
            "evaluator_plan_set_sha256": sha256_json(plans),
        }
    )


def command_plans(args: argparse.Namespace) -> None:
    artifact, raw = load_artifact(args.artifact)
    plans = enumerate_plans(artifact)
    emit(
        {
            "status": "GHOST_OPERATOR_PLANS_V5",
            "opaque_id": artifact.opaque_id,
            "artifact_sha256": hashlib.sha256(raw).hexdigest(),
            "plans": plans,
            "plans_sha256": sha256_json(plans),
        }
    )


def _selected_plan(args: argparse.Namespace, artifact):
    plans = enumerate_plans(artifact)
    if args.method == "reference":
        return reference_plan(artifact), 0, len(plans)
    if args.method == "evaluator_index":
        if args.plan_index is None or not 0 <= args.plan_index < len(plans):
            raise ContractError("--plan-index is outside the enumerated plan set")
        return plans[args.plan_index], args.plan_index, len(plans)
    if args.method == "external_plan":
        if args.plan_path is None:
            raise ContractError("--plan-path is required")
        return load_plan_text(args.plan_path.read_text(encoding="utf-8"), artifact), None, len(plans)
    raise ContractError(f"unknown method: {args.method}")


def command_measure(args: argparse.Namespace) -> None:
    artifact, raw = load_artifact(args.artifact)
    plan, index, plan_count = _selected_plan(args, artifact)
    metrics = measure_plan(
        artifact,
        plan,
        backend=args.backend,
        repetitions=args.repetitions,
        inner_iterations=args.inner_iterations,
    )
    emit(
        {
            "status": "GHOST_OPERATOR_MEASURE_V5",
            "opaque_id": artifact.opaque_id,
            "artifact_sha256": hashlib.sha256(raw).hexdigest(),
            "method": args.method,
            "plan_index": index,
            "evaluator_plan_count": plan_count,
            "plan_sha256": sha256_json(plan),
            "metrics": metrics,
        }
    )


def selftest() -> None:
    from ghost_operator_corpus_v5 import (
        conv_batch_norm,
        dense_matrix_chain,
        explicit_normalization,
        graph_message_passing,
        layout_mlp,
        mamba_projection,
        periodic_diffusion,
    )

    payloads = [
        mamba_projection("test_0", 1, 4, 8, 2, 4, 100),
        graph_message_passing("test_1", 8, 8, 4, 0.25, 100),
        conv_batch_norm("test_2", 1, 4, 8, 8, 100),
        periodic_diffusion("test_3", 1, 8, 8, 100),
        explicit_normalization("test_4", 1, 8, 8, 100),
        layout_mlp("test_5", 1, 4, 4, 4, 8, 100),
        dense_matrix_chain("test_6", 16, 8, 12, 4, 100),
    ]
    expected_counts = [2, 3, 2, 2, 2, 1, 3]
    maximum_error = 0.0
    with tempfile.TemporaryDirectory(prefix="ghost-operator-selftest-") as directory:
        root = pathlib.Path(directory)
        for index, (payload, expected_count) in enumerate(zip(payloads, expected_counts)):
            path = root / f"{index}.json"
            path.write_text(canonical_json(payload) + "\n", encoding="utf-8")
            artifact, _raw = load_artifact(path)
            plans = enumerate_plans(artifact)
            if len(plans) != expected_count:
                raise AssertionError(
                    f"artifact {index} plan count {len(plans)} != {expected_count}"
                )
            for plan in plans:
                loaded = load_plan_text(canonical_json(plan), artifact)
                metrics = measure_plan(
                    artifact,
                    loaded,
                    backend="eager",
                    repetitions=3,
                    inner_iterations=2,
                )
                maximum_error = max(maximum_error, float(metrics["max_abs_error"]))
                if metrics["max_abs_error"] > 1.0e-5:
                    raise AssertionError(f"artifact {index} changed numerically")
                if not metrics["layouts_valid"]:
                    raise AssertionError(f"artifact {index} changed output layout")
    print(
        "GHOST_OPERATOR_EVALUATOR_V5_SELFTEST PASS"
        f" artifacts={len(payloads)} complete_plans={sum(expected_counts)}"
        f" max_abs_error={maximum_error:.9g}"
        " typed=true sparse=true reduction=true normalization=true"
        " layout=true convolution=true state_space=true"
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate = subparsers.add_parser("validate")
    validate.add_argument("artifact", type=pathlib.Path)
    validate.set_defaults(function=command_validate)

    plans = subparsers.add_parser("plans")
    plans.add_argument("artifact", type=pathlib.Path)
    plans.set_defaults(function=command_plans)

    measure = subparsers.add_parser("measure")
    measure.add_argument("artifact", type=pathlib.Path)
    measure.add_argument(
        "method", choices=("reference", "evaluator_index", "external_plan")
    )
    measure.add_argument("--plan-index", type=int)
    measure.add_argument("--plan-path", type=pathlib.Path)
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
        print(f"GHOST_OPERATOR_EVALUATOR_V5 REJECT {exc}", file=sys.stderr)
        raise SystemExit(1) from exc


if __name__ == "__main__":
    main()
