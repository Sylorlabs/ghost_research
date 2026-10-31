#!/usr/bin/env python3
"""Evaluator-owned typed tensor-program IR and CPU replay for Operator v5.

Candidate code must not import this module.  The evaluator owns artifact
validation, whole-program type inference, deterministic tensor construction,
numerical verification, static accounting, compiler invocation, and timing.
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
from collections import Counter
from collections.abc import Mapping, Sequence
from typing import Any


ARTIFACT_VERSION = "GHOST_OPERATOR_ARTIFACT_V5"
PLAN_VERSION = "GHOST_OPERATOR_PLAN_V5"
DTYPE_BYTES = {"float32": 4, "float64": 8}
MAX_TENSOR_ELEMENTS = 64 * 1024 * 1024
MAX_NODES = 256


class ContractError(ValueError):
    """Fail-closed artifact or plan rejection."""


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def sha256_json(value: object) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def file_sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _exact_keys(value: object, keys: set[str], context: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise ContractError(f"{context} fields are not fail-closed")
    return value


def _positive_shape(value: object, context: str, *, allow_scalar: bool = False) -> tuple[int, ...]:
    if not isinstance(value, list):
        raise ContractError(f"{context} shape is not a list")
    shape = tuple(value)
    if not shape and allow_scalar:
        return shape
    if not shape or len(shape) > 6 or any(type(item) is not int or item <= 0 for item in shape):
        raise ContractError(f"{context} shape is invalid")
    if math.prod(shape) > MAX_TENSOR_ELEMENTS:
        raise ContractError(f"{context} shape exceeds the evaluator bound")
    return shape


@dataclasses.dataclass(frozen=True)
class TensorType:
    shape: tuple[int, ...]
    dtype: str
    storage: str = "strided"

    @property
    def elements(self) -> int:
        return math.prod(self.shape)

    @property
    def bytes(self) -> int:
        return self.elements * DTYPE_BYTES[self.dtype]

    def payload(self) -> dict[str, object]:
        return {"shape": list(self.shape), "dtype": self.dtype, "storage": self.storage}


@dataclasses.dataclass(frozen=True)
class InputSpec:
    name: str
    type: TensorType
    seed: int


@dataclasses.dataclass(frozen=True)
class ParameterSpec:
    name: str
    type: TensorType
    seed: int
    init: Mapping[str, object]


@dataclasses.dataclass(frozen=True)
class OutputContract:
    value: str
    type: TensorType
    layout: str


@dataclasses.dataclass(frozen=True)
class Artifact:
    opaque_id: str
    inputs: tuple[InputSpec, ...]
    parameters: tuple[ParameterSpec, ...]
    constants: Mapping[str, object]
    reference_program: Mapping[str, object]
    outputs: tuple[OutputContract, ...]
    reuse_calls: int

    def public_features(self) -> dict[str, int]:
        op_counts = Counter(node["op"] for node in self.reference_program["nodes"])
        input_last_dim = self.inputs[0].type.shape[-1]
        output_last_dim = self.outputs[0].type.shape[-1]
        association_flop_delta = 0
        if op_counts == Counter(
            {"parameter": 2, "matmul": 2, "input": 1}
        ):
            rows, inner_left = self.inputs[0].type.shape
            inner_right = self.parameters[0].type.shape[1]
            columns = self.outputs[0].type.shape[1]
            left_flops = (
                rows * inner_left * inner_right
                + rows * inner_right * columns
            )
            right_flops = (
                inner_left * inner_right * columns
                + rows * inner_left * columns
            )
            association_flop_delta = left_flops - right_flops
        elif op_counts == Counter(
            {
                "parameter": 3,
                "matmul": 2,
                "input": 1,
                "sparse_mm": 1,
                "add": 1,
            }
        ):
            # Both associations share the dense X@W work.  Their difference is
            # nnz(A) * (input_width - output_width), so its sign is exact
            # without relying on a noisy size proxy.
            association_flop_delta = input_last_dim - output_last_dim
        return {
            "input_count": len(self.inputs),
            "parameter_count": len(self.parameters),
            "node_count": len(self.reference_program["nodes"]),
            "reuse_calls": self.reuse_calls,
            "input_elements": sum(item.type.elements for item in self.inputs),
            "parameter_elements": sum(item.type.elements for item in self.parameters),
            "input_last_dim": input_last_dim,
            "output_last_dim": output_last_dim,
            "width_delta": input_last_dim - output_last_dim,
            "association_flop_delta": association_flop_delta,
            "association_right_cheaper": int(association_flop_delta > 0),
            "matmul_count": op_counts["matmul"] + op_counts["linear"] + op_counts["sparse_mm"],
            "conv_count": op_counts["conv2d"],
            "reduction_count": op_counts["reduce_mean"],
            "normalization_count": op_counts["batch_norm_eval"] + op_counts["layer_norm"],
            "layout_count": op_counts["reshape"] + op_counts["permute"],
            "sparse_count": op_counts["sparse_mm"],
        }


def _parse_seed(value: object, context: str) -> int:
    if not isinstance(value, str) or not value.startswith("0x"):
        raise ContractError(f"{context} seed is invalid")
    try:
        seed = int(value[2:], 16)
    except ValueError as exc:
        raise ContractError(f"{context} seed is invalid") from exc
    if seed < 0 or seed >= 2**63:
        raise ContractError(f"{context} seed is outside the protocol")
    return seed


def _parse_type(value: object, context: str, *, storage_allowed: set[str]) -> TensorType:
    payload = _exact_keys(value, {"shape", "dtype", "storage"}, context)
    shape = _positive_shape(payload["shape"], context)
    dtype = payload["dtype"]
    storage = payload["storage"]
    if dtype not in DTYPE_BYTES:
        raise ContractError(f"{context} dtype is unsupported")
    if storage not in storage_allowed:
        raise ContractError(f"{context} storage is unsupported")
    if storage == "sparse_csr" and len(shape) != 2:
        raise ContractError(f"{context} CSR tensor must be rank two")
    return TensorType(shape, dtype, storage)


def _validate_constant(value: object, context: str) -> None:
    if value is None or type(value) in (bool, int, float, str):
        if isinstance(value, float) and not math.isfinite(value):
            raise ContractError(f"{context} is non-finite")
        return
    if isinstance(value, list):
        if len(value) > 128:
            raise ContractError(f"{context} list is too large")
        for index, item in enumerate(value):
            _validate_constant(item, f"{context}[{index}]")
        return
    raise ContractError(f"{context} has unsupported value type")


def _validate_init(init: object, spec_type: TensorType, context: str) -> Mapping[str, object]:
    if not isinstance(init, dict) or "kind" not in init:
        raise ContractError(f"{context} init is invalid")
    kind = init["kind"]
    if spec_type.storage == "sparse_csr":
        _exact_keys(init, {"kind", "density"}, context)
        if kind != "sparse_csr":
            raise ContractError(f"{context} sparse init kind is invalid")
        density = init["density"]
        if type(density) not in (int, float) or not 0.0 < float(density) <= 1.0:
            raise ContractError(f"{context} density is invalid")
        return init
    if kind in ("zeros", "ones"):
        _exact_keys(init, {"kind"}, context)
    elif kind == "literal":
        _exact_keys(init, {"kind", "value"}, context)
        if type(init["value"]) not in (int, float) or not math.isfinite(float(init["value"])):
            raise ContractError(f"{context} literal is invalid")
    elif kind == "normal":
        _exact_keys(init, {"kind", "scale"}, context)
        if type(init["scale"]) not in (int, float) or not 0.0 < float(init["scale"]) <= 10.0:
            raise ContractError(f"{context} scale is invalid")
    elif kind == "positive":
        _exact_keys(init, {"kind", "scale", "offset"}, context)
        if (
            type(init["scale"]) not in (int, float)
            or type(init["offset"]) not in (int, float)
            or not 0.0 < float(init["scale"]) <= 10.0
            or not 0.0 < float(init["offset"]) <= 10.0
        ):
            raise ContractError(f"{context} positive init is invalid")
    else:
        raise ContractError(f"{context} init kind is unsupported")
    return init


def _validate_program_syntax(program: object, context: str) -> Mapping[str, object]:
    payload = _exact_keys(program, {"nodes", "outputs"}, context)
    nodes = payload["nodes"]
    outputs = payload["outputs"]
    if not isinstance(nodes, list) or not 1 <= len(nodes) <= MAX_NODES:
        raise ContractError(f"{context} node count is invalid")
    seen: set[str] = set()
    for index, node in enumerate(nodes):
        item = _exact_keys(node, {"id", "op", "args", "attrs"}, f"{context} node {index}")
        node_id = item["id"]
        if (
            not isinstance(node_id, str)
            or not node_id
            or len(node_id) > 64
            or not node_id.replace("_", "").isalnum()
            or node_id in seen
        ):
            raise ContractError(f"{context} node {index} id is invalid")
        seen.add(node_id)
        if not isinstance(item["op"], str) or not item["op"]:
            raise ContractError(f"{context} node {node_id} op is invalid")
        if not isinstance(item["args"], list) or any(
            not isinstance(arg, str) or arg not in seen for arg in item["args"]
        ):
            raise ContractError(f"{context} node {node_id} has a forward or invalid reference")
        if not isinstance(item["attrs"], dict):
            raise ContractError(f"{context} node {node_id} attrs are invalid")
        for key, value in item["attrs"].items():
            if not isinstance(key, str):
                raise ContractError(f"{context} node {node_id} attr name is invalid")
            _validate_constant(value, f"{context} node {node_id} attr {key}")
    if not isinstance(outputs, list) or not outputs or any(
        not isinstance(item, str) or item not in seen for item in outputs
    ):
        raise ContractError(f"{context} outputs are invalid")
    return payload


def load_artifact(path: pathlib.Path) -> tuple[Artifact, bytes]:
    raw = path.read_bytes()
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ContractError("artifact is not valid JSON") from exc
    root = _exact_keys(
        payload,
        {
            "version",
            "opaque_id",
            "inputs",
            "parameters",
            "constants",
            "reference_program",
            "outputs",
            "reuse_calls",
        },
        "artifact",
    )
    if root["version"] != ARTIFACT_VERSION:
        raise ContractError("artifact version mismatch")
    opaque_id = root["opaque_id"]
    if not isinstance(opaque_id, str) or not opaque_id or len(opaque_id) > 128:
        raise ContractError("opaque id is invalid")

    inputs: list[InputSpec] = []
    names: set[str] = set()
    if not isinstance(root["inputs"], list) or not root["inputs"]:
        raise ContractError("artifact has no inputs")
    for index, value in enumerate(root["inputs"]):
        item = _exact_keys(value, {"name", "type", "seed_hex"}, f"input {index}")
        name = item["name"]
        if not isinstance(name, str) or not name or name in names:
            raise ContractError(f"input {index} name is invalid")
        names.add(name)
        inputs.append(
            InputSpec(
                name,
                _parse_type(item["type"], f"input {name}", storage_allowed={"strided"}),
                _parse_seed(item["seed_hex"], f"input {name}"),
            )
        )

    parameters: list[ParameterSpec] = []
    if not isinstance(root["parameters"], list):
        raise ContractError("artifact parameters are invalid")
    for index, value in enumerate(root["parameters"]):
        item = _exact_keys(
            value, {"name", "type", "seed_hex", "init"}, f"parameter {index}"
        )
        name = item["name"]
        if not isinstance(name, str) or not name or name in names:
            raise ContractError(f"parameter {index} name is invalid")
        names.add(name)
        spec_type = _parse_type(
            item["type"],
            f"parameter {name}",
            storage_allowed={"strided", "sparse_csr"},
        )
        parameters.append(
            ParameterSpec(
                name,
                spec_type,
                _parse_seed(item["seed_hex"], f"parameter {name}"),
                _validate_init(item["init"], spec_type, f"parameter {name}"),
            )
        )

    constants = root["constants"]
    if not isinstance(constants, dict) or len(constants) > 128:
        raise ContractError("artifact constants are invalid")
    for name, value in constants.items():
        if not isinstance(name, str) or not name:
            raise ContractError("artifact constant name is invalid")
        _validate_constant(value, f"constant {name}")

    reference_program = _validate_program_syntax(root["reference_program"], "reference program")
    outputs: list[OutputContract] = []
    if not isinstance(root["outputs"], list) or not root["outputs"]:
        raise ContractError("artifact output contracts are invalid")
    for index, value in enumerate(root["outputs"]):
        item = _exact_keys(value, {"value", "type", "layout"}, f"output {index}")
        if item["layout"] not in ("any", "contiguous", "last_dim_stride_1"):
            raise ContractError(f"output {index} layout is unsupported")
        outputs.append(
            OutputContract(
                item["value"],
                _parse_type(item["type"], f"output {index}", storage_allowed={"strided"}),
                item["layout"],
            )
        )
    if tuple(reference_program["outputs"]) != tuple(item.value for item in outputs):
        raise ContractError("reference outputs do not match output contracts")
    reuse_calls = root["reuse_calls"]
    if type(reuse_calls) is not int or not 1 <= reuse_calls <= 1_000_000:
        raise ContractError("reuse_calls is outside the protocol")

    artifact = Artifact(
        opaque_id,
        tuple(inputs),
        tuple(parameters),
        constants,
        reference_program,
        tuple(outputs),
        reuse_calls,
    )
    inferred = infer_runtime_program(artifact, reference_program, {})
    _check_output_contracts(artifact, reference_program, inferred)
    return artifact, raw


def load_plan_text(text: str, artifact: Artifact) -> Mapping[str, object]:
    try:
        payload = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ContractError("plan is not valid JSON") from exc
    root = _exact_keys(payload, {"version", "parameter_program", "program"}, "plan")
    if root["version"] != PLAN_VERSION:
        raise ContractError("plan version mismatch")
    parameter_program = _validate_parameter_program(root["parameter_program"])
    derived = infer_parameter_program(artifact, parameter_program)
    program = _validate_program_syntax(root["program"], "plan program")
    inferred = infer_runtime_program(artifact, program, derived)
    _check_output_contracts(artifact, program, inferred)
    return root


def reference_plan(artifact: Artifact) -> dict[str, object]:
    return {
        "version": PLAN_VERSION,
        "parameter_program": {"nodes": []},
        "program": artifact.reference_program,
    }


def _constant(artifact: Artifact, name: object, expected: type | tuple[type, ...]) -> Any:
    if not isinstance(name, str) or name not in artifact.constants:
        raise ContractError(f"constant reference {name!r} is invalid")
    value = artifact.constants[name]
    if type(value) not in (expected if isinstance(expected, tuple) else (expected,)):
        raise ContractError(f"constant {name} has the wrong type")
    return value


def _attrs(attrs: Mapping[str, object], expected: set[str], op: str) -> None:
    if set(attrs) != expected:
        raise ContractError(f"{op} attributes are not fail-closed")


def broadcast_shape(left: tuple[int, ...], right: tuple[int, ...]) -> tuple[int, ...]:
    result: list[int] = []
    for a, b in zip(reversed(left), reversed(right)):
        if a != b and a != 1 and b != 1:
            raise ContractError(f"shapes {left} and {right} do not broadcast")
        result.append(max(a, b))
    longer = left if len(left) > len(right) else right
    result.extend(reversed(longer[: abs(len(left) - len(right))]))
    return tuple(reversed(result))


def _matmul_shape(left: tuple[int, ...], right: tuple[int, ...]) -> tuple[int, ...]:
    if not left or not right:
        raise ContractError(f"matmul shapes {left} and {right} are incompatible")
    if len(right) == 1:
        if left[-1] != right[0]:
            raise ContractError(f"matmul shapes {left} and {right} are incompatible")
        if len(left) == 1:
            raise ContractError("scalar matmul results are outside the tensor protocol")
        return left[:-1]
    if len(left) == 1:
        if left[0] != right[-2]:
            raise ContractError(f"matmul shapes {left} and {right} are incompatible")
        return right[:-2] + (right[-1],)
    if left[-1] != right[-2]:
        raise ContractError(f"matmul shapes {left} and {right} are incompatible")
    batch = broadcast_shape(left[:-2], right[:-2])
    return batch + (left[-2], right[-1])


def _conv2d_shape(
    x: tuple[int, ...],
    weight: tuple[int, ...],
    stride: list[int],
    padding: list[int],
    dilation: list[int],
    groups: int,
) -> tuple[int, ...]:
    if len(x) != 4 or len(weight) != 4:
        raise ContractError("conv2d inputs must be rank four")
    if len(stride) != 2 or len(padding) != 2 or len(dilation) != 2:
        raise ContractError("conv2d spatial attributes must have length two")
    n, channels, height, width = x
    out_channels, in_per_group, kernel_h, kernel_w = weight
    if groups <= 0 or channels != in_per_group * groups or out_channels % groups:
        raise ContractError("conv2d groups/channels are inconsistent")
    out_h = (height + 2 * padding[0] - dilation[0] * (kernel_h - 1) - 1) // stride[0] + 1
    out_w = (width + 2 * padding[1] - dilation[1] * (kernel_w - 1) - 1) // stride[1] + 1
    if out_h <= 0 or out_w <= 0:
        raise ContractError("conv2d produces an empty result")
    return (n, out_channels, out_h, out_w)


def _validate_parameter_program(value: object) -> Mapping[str, object]:
    payload = _exact_keys(value, {"nodes"}, "parameter program")
    nodes = payload["nodes"]
    if not isinstance(nodes, list) or len(nodes) > MAX_NODES:
        raise ContractError("parameter program node count is invalid")
    seen: set[str] = set()
    for index, node in enumerate(nodes):
        item = _exact_keys(
            node, {"id", "op", "args", "attrs"}, f"parameter program node {index}"
        )
        node_id = item["id"]
        if (
            not isinstance(node_id, str)
            or not node_id
            or not node_id.replace("_", "").isalnum()
            or node_id in seen
        ):
            raise ContractError(f"parameter program node {index} id is invalid")
        seen.add(node_id)
        if not isinstance(item["op"], str) or not isinstance(item["args"], list):
            raise ContractError(f"parameter program node {node_id} is invalid")
        if not isinstance(item["attrs"], dict):
            raise ContractError(f"parameter program node {node_id} attrs are invalid")
        for attr_name, attr_value in item["attrs"].items():
            _validate_constant(attr_value, f"parameter node {node_id} attr {attr_name}")
    return payload


def infer_parameter_program(
    artifact: Artifact, program: Mapping[str, object]
) -> dict[str, TensorType]:
    environment = {item.name: item.type for item in artifact.parameters}
    derived: dict[str, TensorType] = {}
    for node in program["nodes"]:
        node_id, op, args, attrs = node["id"], node["op"], node["args"], node["attrs"]
        if node_id in environment:
            raise ContractError(f"derived parameter {node_id} shadows a source value")
        if any(arg not in environment for arg in args):
            raise ContractError(f"derived parameter {node_id} has an invalid reference")
        types = [environment[arg] for arg in args]
        if any(item.storage != "strided" for item in types):
            raise ContractError(f"derived parameter {node_id} cannot transform sparse storage")
        if op in ("add", "sub", "mul"):
            _attrs(attrs, set(), op)
            if len(types) != 2 or types[0].dtype != types[1].dtype:
                raise ContractError(f"parameter {op} signature is invalid")
            result = TensorType(broadcast_shape(types[0].shape, types[1].shape), types[0].dtype)
        elif op == "matmul":
            _attrs(attrs, set(), op)
            if len(types) != 2 or types[0].dtype != types[1].dtype:
                raise ContractError("parameter matmul signature is invalid")
            result = TensorType(_matmul_shape(types[0].shape, types[1].shape), types[0].dtype)
        elif op == "cat":
            _attrs(attrs, {"dim"}, op)
            if not types:
                raise ContractError("parameter cat has no arguments")
            dim = attrs["dim"]
            if type(dim) is not int:
                raise ContractError("parameter cat dim is invalid")
            dim %= len(types[0].shape)
            shape = list(types[0].shape)
            if any(item.dtype != types[0].dtype or len(item.shape) != len(shape) for item in types):
                raise ContractError("parameter cat types differ")
            for item in types[1:]:
                if any(a != b for axis, (a, b) in enumerate(zip(shape, item.shape)) if axis != dim):
                    raise ContractError("parameter cat shapes differ")
                shape[dim] += item.shape[dim]
            result = TensorType(tuple(shape), types[0].dtype)
        elif op == "slice":
            _attrs(attrs, {"dim", "start", "length"}, op)
            if len(types) != 1:
                raise ContractError("parameter slice signature is invalid")
            dim, start, length = attrs["dim"], attrs["start"], attrs["length"]
            if any(type(item) is not int for item in (dim, start, length)):
                raise ContractError("parameter slice attributes are invalid")
            dim %= len(types[0].shape)
            if start < 0 or length <= 0 or start + length > types[0].shape[dim]:
                raise ContractError("parameter slice is out of bounds")
            shape = list(types[0].shape)
            shape[dim] = length
            result = TensorType(tuple(shape), types[0].dtype)
        elif op == "reshape":
            _attrs(attrs, {"shape_constant"}, op)
            if len(types) != 1:
                raise ContractError("parameter reshape signature is invalid")
            shape = tuple(_constant(artifact, attrs["shape_constant"], list))
            if any(type(item) is not int or item <= 0 for item in shape) or math.prod(shape) != types[0].elements:
                raise ContractError("parameter reshape shape is invalid")
            result = TensorType(shape, types[0].dtype)
        elif op == "rsqrt_add_scalar":
            _attrs(attrs, {"scalar_constant"}, op)
            if len(types) != 1:
                raise ContractError("rsqrt_add_scalar signature is invalid")
            scalar = _constant(artifact, attrs["scalar_constant"], (int, float))
            if float(scalar) <= 0.0:
                raise ContractError("rsqrt_add_scalar scalar must be positive")
            result = types[0]
        elif op == "neg":
            _attrs(attrs, set(), op)
            if len(types) != 1:
                raise ContractError("parameter neg signature is invalid")
            result = types[0]
        elif op == "stencil_kernel":
            _attrs(attrs, {"center_constant", "neighbor_constant"}, op)
            if args:
                raise ContractError("stencil_kernel has no arguments")
            _constant(artifact, attrs["center_constant"], (int, float))
            _constant(artifact, attrs["neighbor_constant"], (int, float))
            result = TensorType((1, 1, 3, 3), "float32")
        else:
            raise ContractError(f"unsupported parameter construction op: {op}")
        environment[node_id] = result
        derived[node_id] = result
    return derived


def infer_runtime_program(
    artifact: Artifact,
    program: Mapping[str, object],
    derived_parameters: Mapping[str, TensorType],
) -> dict[str, TensorType]:
    input_types = {item.name: item.type for item in artifact.inputs}
    parameter_types = {item.name: item.type for item in artifact.parameters}
    parameter_types.update(derived_parameters)
    environment: dict[str, TensorType] = {}
    for node in program["nodes"]:
        node_id, op, args, attrs = node["id"], node["op"], node["args"], node["attrs"]
        types = [environment[arg] for arg in args]
        if op == "input":
            _attrs(attrs, {"name"}, op)
            if args or attrs["name"] not in input_types:
                raise ContractError("input node signature is invalid")
            result = input_types[attrs["name"]]
        elif op == "parameter":
            _attrs(attrs, {"name"}, op)
            if args or attrs["name"] not in parameter_types:
                raise ContractError("parameter node signature is invalid")
            result = parameter_types[attrs["name"]]
        elif op == "linear":
            _attrs(attrs, set(), op)
            if len(types) not in (2, 3) or types[1].storage != "strided":
                raise ContractError("linear signature is invalid")
            x, weight = types[:2]
            if len(weight.shape) != 2 or x.shape[-1] != weight.shape[1] or x.dtype != weight.dtype:
                raise ContractError("linear shapes are incompatible")
            if len(types) == 3 and (types[2].shape != (weight.shape[0],) or types[2].dtype != x.dtype):
                raise ContractError("linear bias is incompatible")
            result = TensorType(x.shape[:-1] + (weight.shape[0],), x.dtype)
        elif op in ("matmul", "sparse_mm"):
            _attrs(attrs, set(), op)
            if len(types) != 2 or types[0].dtype != types[1].dtype:
                raise ContractError(f"{op} signature is invalid")
            if op == "sparse_mm":
                if types[0].storage != "sparse_csr" or len(types[0].shape) != 2 or len(types[1].shape) != 2:
                    raise ContractError("sparse_mm requires CSR matrix and dense matrix")
            elif any(item.storage != "strided" for item in types):
                raise ContractError("matmul does not accept sparse storage")
            result = TensorType(_matmul_shape(types[0].shape, types[1].shape), types[0].dtype)
        elif op in ("add", "sub", "mul"):
            _attrs(attrs, set(), op)
            if len(types) != 2 or types[0].dtype != types[1].dtype:
                raise ContractError(f"{op} signature is invalid")
            result = TensorType(broadcast_shape(types[0].shape, types[1].shape), types[0].dtype)
        elif op == "cat":
            _attrs(attrs, {"dim"}, op)
            if not types:
                raise ContractError("cat has no inputs")
            dim = attrs["dim"]
            if type(dim) is not int:
                raise ContractError("cat dim is invalid")
            dim %= len(types[0].shape)
            shape = list(types[0].shape)
            for item in types:
                if item.dtype != types[0].dtype or len(item.shape) != len(shape):
                    raise ContractError("cat input types differ")
            for item in types[1:]:
                if any(a != b for axis, (a, b) in enumerate(zip(shape, item.shape)) if axis != dim):
                    raise ContractError("cat input shapes differ")
                shape[dim] += item.shape[dim]
            result = TensorType(tuple(shape), types[0].dtype)
        elif op == "split_get":
            _attrs(attrs, {"dim", "sizes_constant", "index"}, op)
            if len(types) != 1:
                raise ContractError("split_get signature is invalid")
            sizes = _constant(artifact, attrs["sizes_constant"], list)
            dim, index = attrs["dim"], attrs["index"]
            if (
                type(dim) is not int
                or type(index) is not int
                or any(type(item) is not int or item <= 0 for item in sizes)
            ):
                raise ContractError("split_get attributes are invalid")
            dim %= len(types[0].shape)
            if sum(sizes) != types[0].shape[dim] or not 0 <= index < len(sizes):
                raise ContractError("split_get partition is invalid")
            shape = list(types[0].shape)
            shape[dim] = sizes[index]
            result = TensorType(tuple(shape), types[0].dtype)
        elif op == "conv2d":
            _attrs(attrs, {"stride", "padding", "dilation", "groups"}, op)
            if len(types) not in (2, 3):
                raise ContractError("conv2d signature is invalid")
            x, weight = types[:2]
            if x.dtype != weight.dtype or any(item.storage != "strided" for item in types):
                raise ContractError("conv2d types differ")
            shape = _conv2d_shape(
                x.shape,
                weight.shape,
                attrs["stride"],
                attrs["padding"],
                attrs["dilation"],
                attrs["groups"],
            )
            if len(types) == 3 and types[2].shape != (shape[1],):
                raise ContractError("conv2d bias shape is invalid")
            result = TensorType(shape, x.dtype)
        elif op == "batch_norm_eval":
            _attrs(attrs, {"epsilon_constant"}, op)
            if len(types) != 5 or len(types[0].shape) != 4:
                raise ContractError("batch_norm_eval signature is invalid")
            channels = types[0].shape[1]
            if any(item.shape != (channels,) or item.dtype != types[0].dtype for item in types[1:]):
                raise ContractError("batch_norm_eval parameters are incompatible")
            _constant(artifact, attrs["epsilon_constant"], (int, float))
            result = types[0]
        elif op == "layer_norm":
            _attrs(attrs, {"normalized_shape_constant", "epsilon_constant"}, op)
            if len(types) not in (1, 3):
                raise ContractError("layer_norm signature is invalid")
            normalized = tuple(_constant(artifact, attrs["normalized_shape_constant"], list))
            _constant(artifact, attrs["epsilon_constant"], (int, float))
            if tuple(types[0].shape[-len(normalized) :]) != normalized:
                raise ContractError("layer_norm normalized shape is incompatible")
            if len(types) == 3 and (
                types[1].shape != normalized
                or types[2].shape != normalized
                or any(item.dtype != types[0].dtype for item in types[1:])
            ):
                raise ContractError("layer_norm affine parameters are incompatible")
            result = types[0]
        elif op == "reduce_mean":
            _attrs(attrs, {"dims", "keepdim"}, op)
            if len(types) != 1 or not isinstance(attrs["dims"], list) or type(attrs["keepdim"]) is not bool:
                raise ContractError("reduce_mean signature is invalid")
            rank = len(types[0].shape)
            dims = tuple(sorted({int(item) % rank for item in attrs["dims"]}))
            if not dims:
                raise ContractError("reduce_mean dims are empty")
            shape = tuple(
                1 if axis in dims and attrs["keepdim"] else size
                for axis, size in enumerate(types[0].shape)
                if axis not in dims or attrs["keepdim"]
            )
            result = TensorType(shape, types[0].dtype)
        elif op in ("rsqrt", "relu", "silu", "gelu"):
            _attrs(attrs, set(), op)
            if len(types) != 1:
                raise ContractError(f"{op} signature is invalid")
            result = types[0]
        elif op == "reshape":
            _attrs(attrs, {"shape_constant"}, op)
            if len(types) != 1:
                raise ContractError("reshape signature is invalid")
            raw_shape = _constant(artifact, attrs["shape_constant"], list)
            if any(type(item) is not int or item == 0 or item < -1 for item in raw_shape):
                raise ContractError("reshape target is invalid")
            if raw_shape.count(-1) > 1:
                raise ContractError("reshape has multiple inferred dimensions")
            known = math.prod(item for item in raw_shape if item != -1)
            if -1 in raw_shape:
                if known == 0 or types[0].elements % known:
                    raise ContractError("reshape inferred dimension is invalid")
                shape = tuple(types[0].elements // known if item == -1 else item for item in raw_shape)
            else:
                shape = tuple(raw_shape)
            if math.prod(shape) != types[0].elements:
                raise ContractError("reshape changes element count")
            result = TensorType(shape, types[0].dtype)
        elif op == "permute":
            _attrs(attrs, {"dims"}, op)
            if len(types) != 1 or not isinstance(attrs["dims"], list):
                raise ContractError("permute signature is invalid")
            dims = attrs["dims"]
            if sorted(dims) != list(range(len(types[0].shape))):
                raise ContractError("permute dims are invalid")
            result = TensorType(tuple(types[0].shape[index] for index in dims), types[0].dtype)
        elif op == "roll":
            _attrs(attrs, {"shifts", "dims"}, op)
            if (
                len(types) != 1
                or not isinstance(attrs["shifts"], list)
                or not isinstance(attrs["dims"], list)
                or len(attrs["shifts"]) != len(attrs["dims"])
            ):
                raise ContractError("roll signature is invalid")
            result = types[0]
        elif op == "pad_circular":
            _attrs(attrs, {"padding"}, op)
            if len(types) != 1 or len(types[0].shape) != 4 or not isinstance(attrs["padding"], list) or len(attrs["padding"]) != 4:
                raise ContractError("pad_circular signature is invalid")
            left, right, top, bottom = attrs["padding"]
            if any(type(item) is not int or item < 0 for item in attrs["padding"]):
                raise ContractError("pad_circular padding is invalid")
            n, c, h, w = types[0].shape
            result = TensorType((n, c, h + top + bottom, w + left + right), types[0].dtype)
        else:
            raise ContractError(f"unsupported runtime op: {op}")
        environment[node_id] = result
    return environment


def _check_output_contracts(
    artifact: Artifact,
    program: Mapping[str, object],
    inferred: Mapping[str, TensorType],
) -> None:
    if len(program["outputs"]) != len(artifact.outputs):
        raise ContractError("program output arity does not match the artifact")
    for node_id, contract in zip(program["outputs"], artifact.outputs):
        if inferred[node_id] != contract.type:
            raise ContractError(
                f"output {node_id} type {inferred[node_id].payload()} "
                f"does not match {contract.type.payload()}"
            )


def _torch_dtype(dtype: str):
    import torch

    return {"float32": torch.float32, "float64": torch.float64}[dtype]


def _dense_value(spec_type: TensorType, seed: int, init: Mapping[str, object]):
    import torch

    generator = torch.Generator(device="cpu")
    generator.manual_seed(seed)
    kind = init["kind"]
    if kind == "zeros":
        return torch.zeros(spec_type.shape, dtype=_torch_dtype(spec_type.dtype))
    if kind == "ones":
        return torch.ones(spec_type.shape, dtype=_torch_dtype(spec_type.dtype))
    if kind == "literal":
        return torch.full(
            spec_type.shape,
            float(init["value"]),
            dtype=_torch_dtype(spec_type.dtype),
        )
    value = torch.randn(
        spec_type.shape, generator=generator, dtype=_torch_dtype(spec_type.dtype)
    )
    if kind == "normal":
        return value * float(init["scale"])
    if kind == "positive":
        return value.abs() * float(init["scale"]) + float(init["offset"])
    raise AssertionError(kind)


def _parameter_value(spec: ParameterSpec):
    import torch

    if spec.type.storage == "strided":
        return _dense_value(spec.type, spec.seed, spec.init)
    rows, cols = spec.type.shape
    generator = torch.Generator(device="cpu")
    generator.manual_seed(spec.seed)
    mask = torch.rand((rows, cols), generator=generator) < float(spec.init["density"])
    diagonal = min(rows, cols)
    mask[torch.arange(diagonal), torch.arange(diagonal)] = True
    dense = torch.randn(
        (rows, cols), generator=generator, dtype=_torch_dtype(spec.type.dtype)
    ) * mask
    return dense.to_sparse_csr()


def materialize_inputs(artifact: Artifact) -> tuple[Any, ...]:
    result = []
    for spec in artifact.inputs:
        result.append(
            _dense_value(spec.type, spec.seed, {"kind": "normal", "scale": 0.5})
        )
    return tuple(result)


def execute_parameter_program(
    artifact: Artifact,
    program: Mapping[str, object],
    source: Mapping[str, Any],
) -> dict[str, Any]:
    import torch

    environment = dict(source)
    result: dict[str, Any] = {}
    for node in program["nodes"]:
        op, args, attrs = node["op"], node["args"], node["attrs"]
        values = [environment[arg] for arg in args]
        if op == "add":
            value = values[0] + values[1]
        elif op == "sub":
            value = values[0] - values[1]
        elif op == "mul":
            value = values[0] * values[1]
        elif op == "matmul":
            value = torch.matmul(values[0], values[1])
        elif op == "cat":
            value = torch.cat(values, dim=attrs["dim"])
        elif op == "slice":
            slices = [slice(None)] * values[0].ndim
            slices[attrs["dim"]] = slice(attrs["start"], attrs["start"] + attrs["length"])
            value = values[0][tuple(slices)]
        elif op == "reshape":
            value = values[0].reshape(tuple(artifact.constants[attrs["shape_constant"]]))
        elif op == "rsqrt_add_scalar":
            value = torch.rsqrt(
                values[0] + float(artifact.constants[attrs["scalar_constant"]])
            )
        elif op == "neg":
            value = -values[0]
        elif op == "stencil_kernel":
            center = float(artifact.constants[attrs["center_constant"]])
            neighbor = float(artifact.constants[attrs["neighbor_constant"]])
            value = torch.tensor(
                [[[[0.0, neighbor, 0.0], [neighbor, center, neighbor], [0.0, neighbor, 0.0]]]],
                dtype=torch.float32,
            )
        else:
            raise AssertionError(op)
        value = value.detach().contiguous()
        environment[node["id"]] = value
        result[node["id"]] = value
    return result


class TensorProgramModule:
    """Thin factory wrapper returning a real torch.nn.Module."""

    @staticmethod
    def build(artifact: Artifact, plan: Mapping[str, object]):
        import torch
        import torch.nn.functional as functional

        source = {spec.name: _parameter_value(spec) for spec in artifact.parameters}
        started = time.perf_counter_ns()
        derived = execute_parameter_program(artifact, plan["parameter_program"], source)
        construction_us = (time.perf_counter_ns() - started) / 1_000.0

        class Module(torch.nn.Module):
            def __init__(self) -> None:
                super().__init__()
                for name, value in {**source, **derived}.items():
                    self.register_buffer(f"value_{name}", value)

            def forward(self, *runtime_inputs):
                environment: dict[str, Any] = {}
                input_map = {
                    spec.name: value
                    for spec, value in zip(artifact.inputs, runtime_inputs)
                }
                for node in plan["program"]["nodes"]:
                    op, attrs = node["op"], node["attrs"]
                    values = [environment[arg] for arg in node["args"]]
                    if op == "input":
                        value = input_map[attrs["name"]]
                    elif op == "parameter":
                        value = getattr(self, f"value_{attrs['name']}")
                    elif op == "linear":
                        value = functional.linear(
                            values[0], values[1], values[2] if len(values) == 3 else None
                        )
                    elif op == "matmul":
                        value = torch.matmul(values[0], values[1])
                    elif op == "sparse_mm":
                        value = torch.sparse.mm(values[0], values[1])
                    elif op == "add":
                        value = values[0] + values[1]
                    elif op == "sub":
                        value = values[0] - values[1]
                    elif op == "mul":
                        value = values[0] * values[1]
                    elif op == "cat":
                        value = torch.cat(values, dim=attrs["dim"])
                    elif op == "split_get":
                        sizes = artifact.constants[attrs["sizes_constant"]]
                        value = torch.split(values[0], sizes, dim=attrs["dim"])[attrs["index"]]
                    elif op == "conv2d":
                        value = functional.conv2d(
                            values[0],
                            values[1],
                            values[2] if len(values) == 3 else None,
                            stride=attrs["stride"],
                            padding=attrs["padding"],
                            dilation=attrs["dilation"],
                            groups=attrs["groups"],
                        )
                    elif op == "batch_norm_eval":
                        value = functional.batch_norm(
                            values[0],
                            values[3],
                            values[4],
                            values[1],
                            values[2],
                            training=False,
                            eps=float(artifact.constants[attrs["epsilon_constant"]]),
                        )
                    elif op == "layer_norm":
                        value = functional.layer_norm(
                            values[0],
                            artifact.constants[attrs["normalized_shape_constant"]],
                            values[1] if len(values) == 3 else None,
                            values[2] if len(values) == 3 else None,
                            float(artifact.constants[attrs["epsilon_constant"]]),
                        )
                    elif op == "reduce_mean":
                        value = values[0].mean(dim=attrs["dims"], keepdim=attrs["keepdim"])
                    elif op == "rsqrt":
                        value = torch.rsqrt(values[0])
                    elif op == "relu":
                        value = torch.relu(values[0])
                    elif op == "silu":
                        value = functional.silu(values[0])
                    elif op == "gelu":
                        value = functional.gelu(values[0])
                    elif op == "reshape":
                        value = values[0].reshape(
                            tuple(artifact.constants[attrs["shape_constant"]])
                        )
                    elif op == "permute":
                        value = values[0].permute(attrs["dims"])
                    elif op == "roll":
                        value = torch.roll(values[0], attrs["shifts"], attrs["dims"])
                    elif op == "pad_circular":
                        value = functional.pad(values[0], attrs["padding"], mode="circular")
                    else:
                        raise AssertionError(op)
                    environment[node["id"]] = value
                outputs = tuple(environment[item] for item in plan["program"]["outputs"])
                return outputs[0] if len(outputs) == 1 else outputs

        return Module().eval(), construction_us


def _as_tuple(value: Any) -> tuple[Any, ...]:
    return value if isinstance(value, tuple) else (value,)


def _layout_valid(value: Any, layout: str) -> bool:
    if layout == "any":
        return True
    if layout == "contiguous":
        return bool(value.is_contiguous())
    if layout == "last_dim_stride_1":
        return value.ndim == 0 or value.stride(-1) == 1
    raise AssertionError(layout)


def static_metrics(
    artifact: Artifact,
    plan: Mapping[str, object],
    derived_types: Mapping[str, TensorType],
    inferred: Mapping[str, TensorType],
) -> dict[str, object]:
    counts = Counter(node["op"] for node in plan["program"]["nodes"])
    uses = Counter(
        arg for node in plan["program"]["nodes"] for arg in node["args"]
    )
    output_ids = set(plan["program"]["outputs"])
    live: dict[str, int] = {}
    peak = 0
    for node in plan["program"]["nodes"]:
        node_id = node["id"]
        live[node_id] = inferred[node_id].bytes
        peak = max(peak, sum(live.values()))
        for arg in node["args"]:
            uses[arg] -= 1
            if uses[arg] == 0 and arg not in output_ids:
                live.pop(arg, None)
    return {
        "runtime_node_count": len(plan["program"]["nodes"]),
        "parameter_node_count": len(plan["parameter_program"]["nodes"]),
        "logical_matmul_ops": counts["matmul"] + counts["linear"] + counts["sparse_mm"],
        "logical_conv_ops": counts["conv2d"],
        "logical_reduction_ops": counts["reduce_mean"],
        "logical_normalization_ops": counts["batch_norm_eval"] + counts["layer_norm"],
        "logical_layout_ops": counts["reshape"] + counts["permute"] + counts["pad_circular"],
        "logical_sparse_ops": counts["sparse_mm"],
        "derived_parameter_bytes": sum(item.bytes for item in derived_types.values()),
        "static_peak_live_bytes": peak,
        "operator_histogram": dict(sorted(counts.items())),
    }


def measure_plan(
    artifact: Artifact,
    plan: Mapping[str, object],
    *,
    backend: str = "inductor",
    repetitions: int = 9,
    inner_iterations: int | None = None,
) -> dict[str, object]:
    import torch

    if backend not in ("eager", "inductor"):
        raise ContractError("unsupported compiler backend")
    if repetitions < 3 or repetitions > 101:
        raise ContractError("repetitions are outside the protocol")
    torch.set_num_threads(1)
    derived_types = infer_parameter_program(artifact, plan["parameter_program"])
    inferred = infer_runtime_program(artifact, plan["program"], derived_types)
    _check_output_contracts(artifact, plan["program"], inferred)
    inputs = materialize_inputs(artifact)
    reference, _reference_construction = TensorProgramModule.build(
        artifact, reference_plan(artifact)
    )
    candidate, construction_us = TensorProgramModule.build(artifact, plan)
    with torch.no_grad():
        expected = _as_tuple(reference(*inputs))
        actual = _as_tuple(candidate(*inputs))
    max_abs_error = max(
        float((left - right).abs().max().item())
        for left, right in zip(expected, actual)
    )
    max_rel_error = max(
        float(
            ((left - right).abs() / torch.maximum(left.abs(), torch.tensor(1.0e-7))).max().item()
        )
        for left, right in zip(expected, actual)
    )
    layouts_valid = all(
        _layout_valid(value, contract.layout)
        for value, contract in zip(actual, artifact.outputs)
    )
    if not layouts_valid:
        raise ContractError("runtime output violates the layout contract")

    rss_before = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    compile_started = time.perf_counter_ns()
    compiled = candidate if backend == "eager" else torch.compile(candidate, backend="inductor")
    with torch.no_grad():
        compiled_actual = _as_tuple(compiled(*inputs))
    compile_ms = (time.perf_counter_ns() - compile_started) / 1_000_000.0
    rss_after_compile = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    compiled_max_abs_error = max(
        float((left - right).abs().max().item())
        for left, right in zip(expected, compiled_actual)
    )

    if inner_iterations is None:
        approximate_us = max(1.0, compile_ms * 1000.0 if backend == "eager" else 50.0)
        inner_iterations = max(3, min(10_000, int(20_000.0 / approximate_us)))
    if not 1 <= inner_iterations <= 100_000:
        raise ContractError("inner iterations are outside the protocol")
    samples: list[float] = []
    with torch.no_grad():
        for _ in range(3):
            compiled(*inputs)
        for _ in range(repetitions):
            started = time.perf_counter_ns()
            for _ in range(inner_iterations):
                compiled(*inputs)
            elapsed = time.perf_counter_ns() - started
            samples.append(elapsed / 1_000.0 / inner_iterations)
    latency = statistics.median(samples)
    mad = statistics.median(abs(item - latency) for item in samples)
    rss_after_run = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    static = static_metrics(artifact, plan, derived_types, inferred)
    return {
        **static,
        "backend": backend,
        "construction_us": construction_us,
        "compile_ms": compile_ms,
        "latency_us_median": latency,
        "latency_us_mad": mad,
        "inner_iterations": inner_iterations,
        "repetitions": repetitions,
        "reuse_calls": artifact.reuse_calls,
        "amortized_total_us": construction_us + compile_ms * 1000.0 + artifact.reuse_calls * latency,
        "peak_rss_kb": max(rss_after_compile, rss_after_run),
        "rss_delta_kb": max(rss_after_compile, rss_after_run) - rss_before,
        "max_abs_error": max_abs_error,
        "max_rel_error": max_rel_error,
        "compiled_max_abs_error": compiled_max_abs_error,
        "layouts_valid": layouts_valid,
    }


def plan_payload(parameter_nodes: list[dict[str, object]], runtime_program: Mapping[str, object]):
    return {
        "version": PLAN_VERSION,
        "parameter_program": {"nodes": parameter_nodes},
        "program": runtime_program,
    }
