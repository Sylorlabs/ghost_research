#!/usr/bin/env python3
"""Evaluator-owned whole-program rewrite enumeration for Operator v5.

Rewrites are triggered only by typed dataflow patterns.  Opaque ids and
manifest family labels are not consulted.  Each result is a complete runtime
program plus its complete compile-time parameter-construction program.
"""

from __future__ import annotations

from collections import Counter
from collections.abc import Mapping
from typing import Any

from ghost_operator_core_v5 import (
    Artifact,
    canonical_json,
    load_plan_text,
    plan_payload,
    reference_plan,
)


def runtime_node(
    node_id: str, op: str, args: list[str] | None = None, **attrs: object
) -> dict[str, object]:
    return {"id": node_id, "op": op, "args": args or [], "attrs": attrs}


def parameter_node(
    node_id: str, op: str, args: list[str] | None = None, **attrs: object
) -> dict[str, object]:
    return {"id": node_id, "op": op, "args": args or [], "attrs": attrs}


def _nodes(artifact: Artifact) -> list[Mapping[str, Any]]:
    return artifact.reference_program["nodes"]  # type: ignore[return-value]


def _by_id(artifact: Artifact) -> dict[str, Mapping[str, Any]]:
    return {node["id"]: node for node in _nodes(artifact)}


def _only(nodes: list[Mapping[str, Any]], op: str) -> Mapping[str, Any] | None:
    matches = [item for item in nodes if item["op"] == op]
    return matches[0] if len(matches) == 1 else None


def _parameter_name(node: Mapping[str, Any]) -> str | None:
    return node["attrs"]["name"] if node["op"] == "parameter" else None


def _input_name(node: Mapping[str, Any]) -> str | None:
    return node["attrs"]["name"] if node["op"] == "input" else None


def _mamba_composition(artifact: Artifact) -> Mapping[str, object] | None:
    nodes = _nodes(artifact)
    by_id = _by_id(artifact)
    counts = Counter(item["op"] for item in nodes)
    if counts != Counter(
        {
            "parameter": 4,
            "split_get": 3,
            "linear": 2,
            "input": 1,
            "cat": 1,
        }
    ):
        return None
    cat = _only(nodes, "cat")
    if cat is None or len(cat["args"]) != 3:
        return None
    cat_inputs = [by_id[item] for item in cat["args"]]
    delta = next((item for item in cat_inputs if item["op"] == "linear"), None)
    passthrough = [item for item in cat_inputs if item["op"] == "split_get"]
    if delta is None or len(passthrough) != 2:
        return None
    dt = by_id[delta["args"][0]]
    if dt["op"] != "split_get":
        return None
    projected_ids = {item["args"][0] for item in (dt, *passthrough)}
    if len(projected_ids) != 1:
        return None
    projected = by_id[next(iter(projected_ids))]
    if projected["op"] != "linear" or len(projected["args"]) != 3 or len(delta["args"]) != 3:
        return None
    x_node, xw_node, xb_node = (by_id[item] for item in projected["args"])
    dtw_node, dtb_node = (by_id[item] for item in delta["args"][1:])
    names = [
        _input_name(x_node),
        _parameter_name(xw_node),
        _parameter_name(xb_node),
        _parameter_name(dtw_node),
        _parameter_name(dtb_node),
    ]
    if any(item is None for item in names):
        return None
    input_name, xw, xb, dtw, dtb = names
    sizes_name = dt["attrs"]["sizes_constant"]
    sizes = artifact.constants[sizes_name]
    if not isinstance(sizes, list) or len(sizes) != 3:
        return None
    dt_size = sizes[dt["attrs"]["index"]]
    packed = sum(sizes)
    remainder = packed - dt_size
    parameter_nodes = [
        parameter_node("d0", "slice", [xw], dim=0, start=0, length=dt_size),
        parameter_node("d1", "matmul", [dtw, "d0"]),
        parameter_node("d2", "slice", [xw], dim=0, start=dt_size, length=remainder),
        parameter_node("d3", "cat", ["d1", "d2"], dim=0),
        parameter_node("d4", "slice", [xb], dim=0, start=0, length=dt_size),
        parameter_node("d5", "matmul", [dtw, "d4"]),
        parameter_node("d6", "add", ["d5", dtb]),
        parameter_node("d7", "slice", [xb], dim=0, start=dt_size, length=remainder),
        parameter_node("d8", "cat", ["d6", "d7"], dim=0),
    ]
    program = {
        "nodes": [
            runtime_node("r0", "input", name=input_name),
            runtime_node("r1", "parameter", name="d3"),
            runtime_node("r2", "parameter", name="d8"),
            runtime_node("r3", "linear", ["r0", "r1", "r2"]),
        ],
        "outputs": ["r3"],
    }
    return plan_payload(parameter_nodes, program)


def _graph_reassociations(artifact: Artifact) -> list[Mapping[str, object]]:
    nodes = _nodes(artifact)
    by_id = _by_id(artifact)
    counts = Counter(item["op"] for item in nodes)
    if counts != Counter(
        {"parameter": 3, "matmul": 2, "input": 1, "sparse_mm": 1, "add": 1}
    ):
        return []
    addition = _only(nodes, "add")
    sparse = _only(nodes, "sparse_mm")
    if addition is None or sparse is None:
        return []
    x_node = by_id[sparse["args"][1]]
    adj_node = by_id[sparse["args"][0]]
    if _input_name(x_node) is None or _parameter_name(adj_node) is None:
        return []
    matmuls = [by_id[item] for item in addition["args"] if by_id[item]["op"] == "matmul"]
    if len(matmuls) != 2:
        return []
    message = next((item for item in matmuls if item["args"][0] == sparse["id"]), None)
    skip = next((item for item in matmuls if item["args"][0] == x_node["id"]), None)
    if message is None or skip is None:
        return []
    w_node, ws_node = by_id[message["args"][1]], by_id[skip["args"][1]]
    names = (
        _input_name(x_node),
        _parameter_name(adj_node),
        _parameter_name(w_node),
        _parameter_name(ws_node),
    )
    if any(item is None for item in names):
        return []
    input_name, adjacency, weight, skip_weight = names
    right_program = {
        "nodes": [
            runtime_node("r0", "input", name=input_name),
            runtime_node("r1", "parameter", name=adjacency),
            runtime_node("r2", "parameter", name=weight),
            runtime_node("r3", "parameter", name=skip_weight),
            runtime_node("r4", "matmul", ["r0", "r2"]),
            runtime_node("r5", "sparse_mm", ["r1", "r4"]),
            runtime_node("r6", "matmul", ["r0", "r3"]),
            runtime_node("r7", "add", ["r5", "r6"]),
        ],
        "outputs": ["r7"],
    }
    split_constant = next(
        (
            name
            for name, value in artifact.constants.items()
            if isinstance(value, list)
            and len(value) == 2
            and value[0] == value[1]
        ),
        None,
    )
    plans: list[Mapping[str, object]] = [plan_payload([], right_program)]
    if split_constant is not None:
        packed_program = {
            "nodes": [
                runtime_node("r0", "input", name=input_name),
                runtime_node("r1", "parameter", name=adjacency),
                runtime_node("r2", "parameter", name="d0"),
                runtime_node("r3", "matmul", ["r0", "r2"]),
                runtime_node(
                    "r4",
                    "split_get",
                    ["r3"],
                    dim=-1,
                    sizes_constant=split_constant,
                    index=0,
                ),
                runtime_node(
                    "r5",
                    "split_get",
                    ["r3"],
                    dim=-1,
                    sizes_constant=split_constant,
                    index=1,
                ),
                runtime_node("r6", "sparse_mm", ["r1", "r4"]),
                runtime_node("r7", "add", ["r6", "r5"]),
            ],
            "outputs": ["r7"],
        }
        plans.append(
            plan_payload(
                [parameter_node("d0", "cat", [weight, skip_weight], dim=1)],
                packed_program,
            )
        )
    return plans


def _fold_conv_batch_norm(artifact: Artifact) -> Mapping[str, object] | None:
    nodes = _nodes(artifact)
    by_id = _by_id(artifact)
    counts = Counter(item["op"] for item in nodes)
    if counts != Counter(
        {"parameter": 6, "input": 1, "conv2d": 1, "batch_norm_eval": 1}
    ):
        return None
    conv = _only(nodes, "conv2d")
    bn = _only(nodes, "batch_norm_eval")
    if conv is None or bn is None or bn["args"][0] != conv["id"]:
        return None
    x_node = by_id[conv["args"][0]]
    values = [by_id[item] for item in conv["args"][1:] + bn["args"][1:]]
    names = [_input_name(x_node)] + [_parameter_name(item) for item in values]
    if any(item is None for item in names) or len(names) != 7:
        return None
    input_name, weight, bias, gamma, beta, mean, variance = names
    epsilon = bn["attrs"]["epsilon_constant"]
    scale_shape = next(
        (
            name
            for name, value in artifact.constants.items()
            if isinstance(value, list) and len(value) == 4 and value[1:] == [1, 1, 1]
        ),
        None,
    )
    if scale_shape is None:
        return None
    parameter_nodes = [
        parameter_node("d0", "rsqrt_add_scalar", [variance], scalar_constant=epsilon),
        parameter_node("d1", "mul", [gamma, "d0"]),
        parameter_node("d2", "reshape", ["d1"], shape_constant=scale_shape),
        parameter_node("d3", "mul", [weight, "d2"]),
        parameter_node("d4", "sub", [bias, mean]),
        parameter_node("d5", "mul", ["d4", "d1"]),
        parameter_node("d6", "add", ["d5", beta]),
    ]
    program = {
        "nodes": [
            runtime_node("r0", "input", name=input_name),
            runtime_node("r1", "parameter", name="d3"),
            runtime_node("r2", "parameter", name="d6"),
            runtime_node("r3", "conv2d", ["r0", "r1", "r2"], **conv["attrs"]),
        ],
        "outputs": ["r3"],
    }
    return plan_payload(parameter_nodes, program)


def _stencil_convolution(artifact: Artifact) -> Mapping[str, object] | None:
    nodes = _nodes(artifact)
    counts = Counter(item["op"] for item in nodes)
    if counts["roll"] != 4 or counts["conv2d"] or counts["mul"] != 2:
        return None
    input_node = _only(nodes, "input")
    if input_node is None:
        return None
    center = next(
        (name for name, value in artifact.constants.items() if value == 0.96), None
    )
    neighbor = next(
        (name for name, value in artifact.constants.items() if value == 0.01), None
    )
    if center is None or neighbor is None:
        return None
    program = {
        "nodes": [
            runtime_node("r0", "input", name=_input_name(input_node)),
            runtime_node("r1", "parameter", name="d0"),
            runtime_node("r2", "pad_circular", ["r0"], padding=[1, 1, 1, 1]),
            runtime_node(
                "r3",
                "conv2d",
                ["r2", "r1"],
                stride=[1, 1],
                padding=[0, 0],
                dilation=[1, 1],
                groups=1,
            ),
        ],
        "outputs": ["r3"],
    }
    return plan_payload(
        [
            parameter_node(
                "d0",
                "stencil_kernel",
                center_constant=center,
                neighbor_constant=neighbor,
            )
        ],
        program,
    )


def _primitive_layer_norm(artifact: Artifact) -> Mapping[str, object] | None:
    nodes = _nodes(artifact)
    by_id = _by_id(artifact)
    counts = Counter(item["op"] for item in nodes)
    if counts["reduce_mean"] != 2 or counts["rsqrt"] != 1 or counts["layer_norm"]:
        return None
    input_node = _only(nodes, "input")
    if input_node is None:
        return None
    parameter_nodes = [item for item in nodes if item["op"] == "parameter"]
    if len(parameter_nodes) != 3:
        return None
    # Gamma and beta are the two width-shaped parameters; epsilon is scalar.
    typed = {item.name: item.type for item in artifact.parameters}
    width_parameters = [
        item for item in parameter_nodes if typed[_parameter_name(item)].shape != (1,)
    ]
    if len(width_parameters) != 2:
        return None
    gamma, beta = (_parameter_name(item) for item in width_parameters)
    normalized = next(
        (
            name
            for name, value in artifact.constants.items()
            if isinstance(value, list) and len(value) == 1
        ),
        None,
    )
    epsilon = next(
        (
            name
            for name, value in artifact.constants.items()
            if type(value) is float and 0.0 < value < 0.01
        ),
        None,
    )
    if gamma is None or beta is None or normalized is None or epsilon is None:
        return None
    program = {
        "nodes": [
            runtime_node("r0", "input", name=_input_name(input_node)),
            runtime_node("r1", "parameter", name=gamma),
            runtime_node("r2", "parameter", name=beta),
            runtime_node(
                "r3",
                "layer_norm",
                ["r0", "r1", "r2"],
                normalized_shape_constant=normalized,
                epsilon_constant=epsilon,
            ),
        ],
        "outputs": ["r3"],
    }
    return plan_payload([], program)


def _dense_matrix_chain(artifact: Artifact) -> list[Mapping[str, object]]:
    nodes = _nodes(artifact)
    by_id = _by_id(artifact)
    counts = Counter(item["op"] for item in nodes)
    if counts != Counter({"matmul": 2, "parameter": 2, "input": 1}):
        return []
    output = by_id[artifact.reference_program["outputs"][0]]
    if output["op"] != "matmul":
        return []
    left = by_id[output["args"][0]]
    c_node = by_id[output["args"][1]]
    if left["op"] != "matmul":
        return []
    a_node, b_node = (by_id[item] for item in left["args"])
    names = (
        _input_name(a_node),
        _parameter_name(b_node),
        _parameter_name(c_node),
    )
    if any(item is None for item in names):
        return []
    input_name, b_name, c_name = names
    right_program = {
        "nodes": [
            runtime_node("r0", "input", name=input_name),
            runtime_node("r1", "parameter", name=b_name),
            runtime_node("r2", "parameter", name=c_name),
            runtime_node("r3", "matmul", ["r1", "r2"]),
            runtime_node("r4", "matmul", ["r0", "r3"]),
        ],
        "outputs": ["r4"],
    }
    composed_program = {
        "nodes": [
            runtime_node("r0", "input", name=input_name),
            runtime_node("r1", "parameter", name="d0"),
            runtime_node("r2", "matmul", ["r0", "r1"]),
        ],
        "outputs": ["r2"],
    }
    return [
        plan_payload([], right_program),
        plan_payload(
            [parameter_node("d0", "matmul", [b_name, c_name])],
            composed_program,
        ),
    ]


def enumerate_plans(artifact: Artifact) -> list[Mapping[str, object]]:
    candidates: list[Mapping[str, object]] = [reference_plan(artifact)]
    optional = [
        _mamba_composition(artifact),
        *_graph_reassociations(artifact),
        _fold_conv_batch_norm(artifact),
        _stencil_convolution(artifact),
        _primitive_layer_norm(artifact),
        *_dense_matrix_chain(artifact),
    ]
    candidates.extend(item for item in optional if item is not None)
    unique: dict[str, Mapping[str, object]] = {}
    for candidate in candidates:
        # The evaluator validates every constructed whole program before it can
        # enter the search space.
        validated = load_plan_text(canonical_json(candidate), artifact)
        unique.setdefault(canonical_json(validated), validated)
    return list(unique.values())


def structural_signature(artifact: Artifact) -> str:
    """Candidate-visible canonical typed graph key, excluding sizes and ids."""
    nodes = _nodes(artifact)
    local_index = {node["id"]: index for index, node in enumerate(nodes)}
    payload = []
    for node in nodes:
        attrs = {
            key: (
                {
                    "constant_type": type(artifact.constants[value]).__name__,
                    "list_length": (
                        len(artifact.constants[value])
                        if isinstance(artifact.constants[value], list)
                        else None
                    ),
                }
                if key.endswith("_constant") and isinstance(value, str)
                else value
            )
            for key, value in node["attrs"].items()
            if key != "name"
        }
        payload.append(
            {
                "op": node["op"],
                "args": [local_index[item] for item in node["args"]],
                "attrs": attrs,
            }
        )
    return canonical_json(payload)
