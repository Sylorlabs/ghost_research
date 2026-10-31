#!/usr/bin/env python3
"""Evaluator-side typed tensor IR and CPU measurement support.

Candidate code must not import this module.  It contains artifact validation,
partition enumeration, PyTorch materialization, compiler execution, and
measurement logic owned by the evaluator.
"""

from __future__ import annotations

import dataclasses
import hashlib
import json
import math
import pathlib
import resource
import statistics
import time
from collections.abc import Iterable, Sequence
from typing import Any


ARTIFACT_VERSION = "GHOST_TENSOR_ARTIFACT_V4"
PLAN_VERSION = "GHOST_TENSOR_PLAN_V4"
DTYPE_BYTES = {"float32": 4, "float64": 8}


class ContractError(ValueError):
    pass


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def sha256_json(value: object) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


@dataclasses.dataclass(frozen=True)
class Projection:
    opaque_parameter: str
    out_features: int
    heads: int
    bias: bool

    @property
    def head_dim(self) -> int:
        return self.out_features // self.heads


@dataclasses.dataclass(frozen=True)
class Artifact:
    opaque_id: str
    input_shape: tuple[int, int, int]
    dtype: str
    layout: str
    projections: tuple[Projection, ...]
    weight_seed: int
    output_contract: str

    @property
    def batch(self) -> int:
        return self.input_shape[0]

    @property
    def tokens(self) -> int:
        return self.input_shape[0] * self.input_shape[1]

    @property
    def in_features(self) -> int:
        return self.input_shape[2]

    @property
    def total_out(self) -> int:
        return sum(item.out_features for item in self.projections)

    @property
    def work(self) -> int:
        return self.tokens * self.in_features * self.total_out

    def features(self) -> dict[str, int]:
        return {
            "batch": self.batch,
            "sequence": self.input_shape[1],
            "tokens": self.tokens,
            "in_features": self.in_features,
            "total_out": self.total_out,
            "projection_count": len(self.projections),
            "work": self.work,
            "has_bias": int(any(item.bias for item in self.projections)),
            "heterogeneous_out": int(
                len({item.out_features for item in self.projections}) > 1
            ),
        }


def load_artifact(path: pathlib.Path) -> tuple[Artifact, bytes]:
    raw = path.read_bytes()
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ContractError("artifact is not valid JSON") from exc
    if payload.get("version") != ARTIFACT_VERSION:
        raise ContractError("artifact version mismatch")
    expected = {
        "version",
        "opaque_id",
        "input",
        "projections",
        "weight_seed_hex",
        "output_contract",
    }
    if set(payload) != expected:
        raise ContractError("artifact fields are not fail-closed")
    input_spec = payload["input"]
    if set(input_spec) != {"shape", "dtype", "layout"}:
        raise ContractError("input type fields are invalid")
    shape = tuple(input_spec["shape"])
    if (
        len(shape) != 3
        or any(type(value) is not int or value <= 0 for value in shape)
        or shape[2] > 4096
    ):
        raise ContractError("invalid input shape")
    dtype = input_spec["dtype"]
    if dtype not in DTYPE_BYTES:
        raise ContractError("unsupported dtype")
    if input_spec["layout"] != "contiguous":
        raise ContractError("unsupported input layout")
    projections: list[Projection] = []
    for index, item in enumerate(payload["projections"]):
        if set(item) != {"opaque_parameter", "out_features", "heads", "bias"}:
            raise ContractError("projection fields are invalid")
        out_features = item["out_features"]
        heads = item["heads"]
        if (
            type(out_features) is not int
            or type(heads) is not int
            or out_features <= 0
            or heads <= 0
            or out_features % heads
        ):
            raise ContractError("projection shape is invalid")
        if type(item["bias"]) is not bool:
            raise ContractError("projection bias flag is invalid")
        if item["opaque_parameter"] != f"p{index}":
            raise ContractError("projection identity is noncanonical")
        projections.append(
            Projection(item["opaque_parameter"], out_features, heads, item["bias"])
        )
    if not (2 <= len(projections) <= 6):
        raise ContractError("projection count is outside the protocol")
    if len({item.bias for item in projections}) != 1:
        raise ContractError("mixed bias clusters are not supported")
    if payload["output_contract"] != "BHTD_last_dim_stride_1":
        raise ContractError("output contract mismatch")
    try:
        seed = int(payload["weight_seed_hex"].removeprefix("0x"), 16)
    except (AttributeError, ValueError) as exc:
        raise ContractError("invalid weight seed") from exc
    artifact = Artifact(
        opaque_id=payload["opaque_id"],
        input_shape=shape,
        dtype=dtype,
        layout=input_spec["layout"],
        projections=tuple(projections),
        weight_seed=seed,
        output_contract=payload["output_contract"],
    )
    return artifact, raw


def canonical_partition(groups: Iterable[Iterable[int]], count: int) -> tuple[tuple[int, ...], ...]:
    normalized = tuple(sorted((tuple(sorted(group)) for group in groups), key=lambda group: group[0]))
    if any(not group for group in normalized):
        raise ContractError("empty plan group")
    flat = tuple(index for group in normalized for index in group)
    if sorted(flat) != list(range(count)) or len(set(flat)) != count:
        raise ContractError("plan is not an exact projection partition")
    return normalized


def plan_payload(groups: Iterable[Iterable[int]], count: int) -> dict[str, object]:
    partition = canonical_partition(groups, count)
    return {"version": PLAN_VERSION, "groups": [list(group) for group in partition]}


def plan_key(groups: Iterable[Iterable[int]], count: int) -> str:
    return canonical_json(plan_payload(groups, count))


def load_plan_text(text: str, count: int) -> tuple[tuple[int, ...], ...]:
    try:
        payload = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ContractError("plan is not valid JSON") from exc
    if set(payload) != {"version", "groups"} or payload["version"] != PLAN_VERSION:
        raise ContractError("plan shape is invalid")
    return canonical_partition(payload["groups"], count)


def set_partitions(count: int) -> list[tuple[tuple[int, ...], ...]]:
    if count <= 0:
        return []
    result: list[tuple[tuple[int, ...], ...]] = []

    def visit(index: int, groups: list[list[int]]) -> None:
        if index == count:
            result.append(canonical_partition(groups, count))
            return
        for group_index in range(len(groups)):
            groups[group_index].append(index)
            visit(index + 1, groups)
            groups[group_index].pop()
        groups.append([index])
        visit(index + 1, groups)
        groups.pop()

    visit(0, [])
    return sorted(set(result), key=lambda groups: (len(groups), groups))


def identity_partition(count: int) -> tuple[tuple[int, ...], ...]:
    return tuple((index,) for index in range(count))


def packed_partition(count: int) -> tuple[tuple[int, ...], ...]:
    return (tuple(range(count)),)


def random_partition(count: int, seed: int) -> tuple[tuple[int, ...], ...]:
    import random

    choices = set_partitions(count)
    return choices[random.Random(seed).randrange(len(choices))]


def parameter_bytes(artifact: Artifact) -> int:
    scalars = 0
    for projection in artifact.projections:
        scalars += projection.out_features * artifact.in_features
        if projection.bias:
            scalars += projection.out_features
    return scalars * DTYPE_BYTES[artifact.dtype]


def tensor_bytes(shape: Sequence[int], dtype: str) -> int:
    return math.prod(shape) * DTYPE_BYTES[dtype]


def static_metrics(
    artifact: Artifact,
    groups: tuple[tuple[int, ...], ...],
) -> dict[str, int]:
    output_bytes = sum(
        tensor_bytes(
            (
                artifact.batch,
                projection.heads,
                artifact.input_shape[1],
                projection.head_dim,
            ),
            artifact.dtype,
        )
        for projection in artifact.projections
    )
    packed_groups = sum(len(group) > 1 for group in groups)
    split_views = sum(len(group) for group in groups if len(group) > 1)
    return {
        "logical_gemm_kernels": len(groups),
        "logical_linear_ops": len(groups),
        "logical_split_views": split_views,
        "logical_head_views": len(artifact.projections),
        "logical_transposes": len(artifact.projections),
        "packed_groups": packed_groups,
        "parameter_bytes": parameter_bytes(artifact),
        "input_bytes": tensor_bytes(artifact.input_shape, artifact.dtype),
        "output_bytes": output_bytes,
        "analytic_peak_live_tensor_bytes": tensor_bytes(
            artifact.input_shape, artifact.dtype
        )
        + output_bytes,
        "multiply_adds": artifact.work,
    }


def build_module(artifact: Artifact, groups: tuple[tuple[int, ...], ...]):
    import torch
    import torch.nn as nn
    import torch.nn.functional as functional

    dtype = torch.float32 if artifact.dtype == "float32" else torch.float64
    generator = torch.Generator(device="cpu")
    generator.manual_seed(artifact.weight_seed & ((1 << 63) - 1))
    base_weights: list[torch.Tensor] = []
    base_biases: list[torch.Tensor | None] = []
    scale = 1.0 / math.sqrt(artifact.in_features)
    for projection in artifact.projections:
        weight = torch.randn(
            projection.out_features,
            artifact.in_features,
            generator=generator,
            dtype=dtype,
        ) * scale
        bias = (
            torch.randn(
                projection.out_features,
                generator=generator,
                dtype=dtype,
            )
            * scale
            if projection.bias
            else None
        )
        base_weights.append(weight)
        base_biases.append(bias)

    class ProjectionModule(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.group_weights = nn.ParameterList()
            self.group_biases = nn.ParameterList()
            self.group_has_bias: list[bool] = []
            self.group_outputs: list[tuple[int, ...]] = []
            self.group_sizes: list[tuple[int, ...]] = []
            for group in groups:
                self.group_weights.append(
                    nn.Parameter(torch.cat([base_weights[index] for index in group]))
                )
                biases = [base_biases[index] for index in group]
                has_bias = all(item is not None for item in biases)
                self.group_has_bias.append(has_bias)
                if has_bias:
                    self.group_biases.append(
                        nn.Parameter(torch.cat([item for item in biases if item is not None]))
                    )
                else:
                    self.group_biases.append(
                        nn.Parameter(torch.empty(0, dtype=dtype), requires_grad=False)
                    )
                self.group_outputs.append(group)
                self.group_sizes.append(
                    tuple(artifact.projections[index].out_features for index in group)
                )

        def forward(self, tensor):
            outputs: list[Any] = [None] * len(artifact.projections)
            for group_index, group in enumerate(self.group_outputs):
                bias = (
                    self.group_biases[group_index]
                    if self.group_has_bias[group_index]
                    else None
                )
                projected = functional.linear(
                    tensor,
                    self.group_weights[group_index],
                    bias,
                )
                pieces = (
                    (projected,)
                    if len(group) == 1
                    else projected.split(self.group_sizes[group_index], dim=-1)
                )
                for projection_index, piece in zip(group, pieces, strict=True):
                    projection = artifact.projections[projection_index]
                    outputs[projection_index] = piece.view(
                        artifact.input_shape[0],
                        artifact.input_shape[1],
                        projection.heads,
                        projection.head_dim,
                    ).transpose(1, 2)
            return tuple(outputs)

    module = ProjectionModule().eval()
    input_generator = torch.Generator(device="cpu")
    input_generator.manual_seed((artifact.weight_seed ^ 0x51F15EED) & ((1 << 63) - 1))
    sample = torch.randn(artifact.input_shape, generator=input_generator, dtype=dtype)
    return module, sample


def output_contract(artifact: Artifact, outputs: Sequence[Any]) -> list[dict[str, object]]:
    import torch

    if len(outputs) != len(artifact.projections):
        raise ContractError("output arity changed")
    contracts: list[dict[str, object]] = []
    for projection, tensor in zip(artifact.projections, outputs, strict=True):
        expected_shape = (
            artifact.input_shape[0],
            projection.heads,
            artifact.input_shape[1],
            projection.head_dim,
        )
        if tuple(tensor.shape) != expected_shape:
            raise ContractError("output shape changed")
        expected_dtype = torch.float32 if artifact.dtype == "float32" else torch.float64
        if tensor.dtype != expected_dtype:
            raise ContractError("output dtype changed")
        if tensor.stride(-1) != 1:
            raise ContractError("output last dimension lost unit stride")
        contracts.append(
            {
                "shape": list(tensor.shape),
                "dtype": str(tensor.dtype).removeprefix("torch."),
                "stride": list(tensor.stride()),
                "last_dim_stride_1": True,
            }
        )
    return contracts


def compare_outputs(reference: Sequence[Any], candidate: Sequence[Any]) -> dict[str, float]:
    import torch

    maximum_absolute = 0.0
    maximum_relative = 0.0
    for expected, actual in zip(reference, candidate, strict=True):
        difference = (expected - actual).abs()
        maximum_absolute = max(maximum_absolute, float(difference.max().item()))
        denominator = expected.abs().clamp_min(torch.finfo(expected.dtype).tiny)
        maximum_relative = max(
            maximum_relative,
            float((difference / denominator).max().item()),
        )
    return {"max_abs_error": maximum_absolute, "max_rel_error": maximum_relative}


def current_rss_kb() -> int:
    for line in pathlib.Path("/proc/self/status").read_text(encoding="utf-8").splitlines():
        if line.startswith("VmRSS:"):
            return int(line.split()[1])
    return 0


def measure_plan(
    artifact: Artifact,
    groups: tuple[tuple[int, ...], ...],
    *,
    repetitions: int = 9,
    inner_iterations: int | None = None,
    compile_backend: str = "inductor",
) -> dict[str, object]:
    import torch

    torch.set_num_threads(1)
    if torch.get_num_interop_threads() != 1:
        torch.set_num_interop_threads(1)
    torch.manual_seed(0)
    reference_module, sample = build_module(
        artifact, identity_partition(len(artifact.projections))
    )
    module, candidate_sample = build_module(artifact, groups)
    with torch.inference_mode():
        reference = reference_module(sample)
        eager_candidate = module(candidate_sample)
    contract = output_contract(artifact, eager_candidate)
    errors = compare_outputs(reference, eager_candidate)
    absolute_tolerance = 1e-4 if artifact.dtype == "float32" else 1e-12
    relative_tolerance = 2e-5 if artifact.dtype == "float32" else 1e-12
    if any(
        not torch.allclose(
            expected,
            actual,
            rtol=relative_tolerance,
            atol=absolute_tolerance,
        )
        for expected, actual in zip(reference, eager_candidate, strict=True)
    ):
        raise ContractError("candidate plan failed eager numerical equivalence")

    rss_before = current_rss_kb()
    compile_started = time.perf_counter_ns()
    inductor_metrics = None
    if compile_backend == "eager":
        compiled = module
    elif compile_backend == "inductor":
        from torch._inductor import metrics as inductor_metrics

        inductor_metrics.reset()
        compiled = torch.compile(module, backend="inductor", fullgraph=True, dynamic=False)
    else:
        raise ContractError("unknown compiler backend")
    with torch.inference_mode():
        compiled_output = compiled(candidate_sample)
    compile_ms = (time.perf_counter_ns() - compile_started) / 1_000_000.0
    output_contract(artifact, compiled_output)
    compiled_errors = compare_outputs(reference, compiled_output)
    if any(
        not torch.allclose(
            expected,
            actual,
            rtol=relative_tolerance,
            atol=absolute_tolerance,
        )
        for expected, actual in zip(reference, compiled_output, strict=True)
    ):
        raise ContractError("compiled plan failed numerical equivalence")

    if inner_iterations is None:
        target_calls = max(20, min(1000, 4_000_000 // max(1, artifact.work)))
        inner_iterations = target_calls
    with torch.inference_mode():
        for _ in range(20):
            compiled(candidate_sample)
        timings: list[float] = []
        for _ in range(repetitions):
            started = time.perf_counter_ns()
            for _ in range(inner_iterations):
                compiled(candidate_sample)
            elapsed = time.perf_counter_ns() - started
            timings.append(elapsed / inner_iterations / 1_000.0)
    rss_after = max(
        current_rss_kb(),
        int(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss),
    )
    ordered = sorted(timings)
    median_latency = statistics.median(ordered)
    median_absolute_deviation = statistics.median(
        abs(value - median_latency) for value in ordered
    )
    metrics: dict[str, object] = {
        "artifact_sha256": None,
        "plan": plan_payload(groups, len(artifact.projections)),
        "plan_sha256": sha256_json(plan_payload(groups, len(artifact.projections))),
        "compiler": compile_backend,
        "compile_ms": compile_ms,
        "latency_us_median": median_latency,
        "latency_us_mad": median_absolute_deviation,
        "latency_samples_us": ordered,
        "inner_iterations": inner_iterations,
        "repetitions": repetitions,
        "rss_before_kb": rss_before,
        "peak_rss_kb": rss_after,
        "rss_delta_kb": max(0, rss_after - rss_before),
        "output_contracts": contract,
        "absolute_tolerance": absolute_tolerance,
        "relative_tolerance": relative_tolerance,
        **errors,
        "compiled_max_abs_error": compiled_errors["max_abs_error"],
        "compiled_max_rel_error": compiled_errors["max_rel_error"],
        **static_metrics(artifact, groups),
    }
    if inductor_metrics is not None:
        metrics.update(
            {
                "inductor_generated_kernel_count": int(
                    inductor_metrics.generated_kernel_count
                ),
                "inductor_generated_cpp_vec_kernel_count": int(
                    inductor_metrics.generated_cpp_vec_kernel_count
                ),
                "inductor_ir_nodes_pre_fusion": int(
                    inductor_metrics.ir_nodes_pre_fusion
                ),
                "inductor_num_bytes_accessed": int(
                    inductor_metrics.num_bytes_accessed
                ),
            }
        )
    return metrics
