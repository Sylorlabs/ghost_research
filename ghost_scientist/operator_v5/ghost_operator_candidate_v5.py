#!/usr/bin/env python3
"""Frozen-candidate shape for Operator v5 (development, not frozen yet).

This module is intentionally evaluator-independent.  It parses only JSON,
recognizes typed dataflow structure, constructs whole candidate programs, and
uses a learned grammar to choose among them.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import pathlib
import sys
from collections import Counter
from collections.abc import Mapping, Sequence
from typing import Any


ARTIFACT_VERSION = "GHOST_OPERATOR_ARTIFACT_V5"
PLAN_VERSION = "GHOST_OPERATOR_PLAN_V5"
GRAMMAR_VERSION = "GHOST_OPERATOR_GRAMMAR_V5"


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def runtime_node(node_id: str, op: str, args=None, **attrs):
    return {"id": node_id, "op": op, "args": args or [], "attrs": attrs}


def parameter_node(node_id: str, op: str, args=None, **attrs):
    return {"id": node_id, "op": op, "args": args or [], "attrs": attrs}


def plan(parameter_nodes, program):
    return {
        "version": PLAN_VERSION,
        "parameter_program": {"nodes": parameter_nodes},
        "program": program,
    }


def reference_plan(payload):
    return plan([], payload["reference_program"])


def nodes(payload):
    return payload["reference_program"]["nodes"]


def by_id(payload):
    return {item["id"]: item for item in nodes(payload)}


def only(items, op):
    matches = [item for item in items if item["op"] == op]
    return matches[0] if len(matches) == 1 else None


def value_name(node, op):
    return node["attrs"]["name"] if node["op"] == op else None


def mamba_composition(payload):
    items, lookup = nodes(payload), by_id(payload)
    if Counter(item["op"] for item in items) != Counter(
        {"parameter": 4, "split_get": 3, "linear": 2, "input": 1, "cat": 1}
    ):
        return None
    cat = only(items, "cat")
    cat_inputs = [lookup[item] for item in cat["args"]] if cat else []
    delta = next((item for item in cat_inputs if item["op"] == "linear"), None)
    passthrough = [item for item in cat_inputs if item["op"] == "split_get"]
    if delta is None or len(passthrough) != 2:
        return None
    dt = lookup[delta["args"][0]]
    projected_ids = {item["args"][0] for item in (dt, *passthrough)}
    if dt["op"] != "split_get" or len(projected_ids) != 1:
        return None
    projected = lookup[next(iter(projected_ids))]
    if projected["op"] != "linear" or len(projected["args"]) != 3:
        return None
    x, xw, xb = (lookup[item] for item in projected["args"])
    dtw, dtb = (lookup[item] for item in delta["args"][1:])
    names = [
        value_name(x, "input"),
        value_name(xw, "parameter"),
        value_name(xb, "parameter"),
        value_name(dtw, "parameter"),
        value_name(dtb, "parameter"),
    ]
    if any(item is None for item in names):
        return None
    input_name, xw_name, xb_name, dtw_name, dtb_name = names
    sizes_name = dt["attrs"]["sizes_constant"]
    sizes = payload["constants"][sizes_name]
    dt_size, packed = sizes[dt["attrs"]["index"]], sum(sizes)
    derived = [
        parameter_node("d0", "slice", [xw_name], dim=0, start=0, length=dt_size),
        parameter_node("d1", "matmul", [dtw_name, "d0"]),
        parameter_node("d2", "slice", [xw_name], dim=0, start=dt_size, length=packed - dt_size),
        parameter_node("d3", "cat", ["d1", "d2"], dim=0),
        parameter_node("d4", "slice", [xb_name], dim=0, start=0, length=dt_size),
        parameter_node("d5", "matmul", [dtw_name, "d4"]),
        parameter_node("d6", "add", ["d5", dtb_name]),
        parameter_node("d7", "slice", [xb_name], dim=0, start=dt_size, length=packed - dt_size),
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
    return plan(derived, program)


def graph_reassociations(payload):
    items, lookup = nodes(payload), by_id(payload)
    if Counter(item["op"] for item in items) != Counter(
        {"parameter": 3, "matmul": 2, "input": 1, "sparse_mm": 1, "add": 1}
    ):
        return []
    addition, sparse = only(items, "add"), only(items, "sparse_mm")
    if addition is None or sparse is None:
        return []
    x, adjacency = lookup[sparse["args"][1]], lookup[sparse["args"][0]]
    products = [lookup[item] for item in addition["args"] if lookup[item]["op"] == "matmul"]
    message = next((item for item in products if item["args"][0] == sparse["id"]), None)
    skip = next((item for item in products if item["args"][0] == x["id"]), None)
    if message is None or skip is None:
        return []
    names = (
        value_name(x, "input"),
        value_name(adjacency, "parameter"),
        value_name(lookup[message["args"][1]], "parameter"),
        value_name(lookup[skip["args"][1]], "parameter"),
    )
    if any(item is None for item in names):
        return []
    input_name, adjacency_name, weight, skip_weight = names
    right = {
        "nodes": [
            runtime_node("r0", "input", name=input_name),
            runtime_node("r1", "parameter", name=adjacency_name),
            runtime_node("r2", "parameter", name=weight),
            runtime_node("r3", "parameter", name=skip_weight),
            runtime_node("r4", "matmul", ["r0", "r2"]),
            runtime_node("r5", "sparse_mm", ["r1", "r4"]),
            runtime_node("r6", "matmul", ["r0", "r3"]),
            runtime_node("r7", "add", ["r5", "r6"]),
        ],
        "outputs": ["r7"],
    }
    result = [plan([], right)]
    split = next(
        (
            name
            for name, value in payload["constants"].items()
            if isinstance(value, list) and len(value) == 2 and value[0] == value[1]
        ),
        None,
    )
    if split is not None:
        packed = {
            "nodes": [
                runtime_node("r0", "input", name=input_name),
                runtime_node("r1", "parameter", name=adjacency_name),
                runtime_node("r2", "parameter", name="d0"),
                runtime_node("r3", "matmul", ["r0", "r2"]),
                runtime_node("r4", "split_get", ["r3"], dim=-1, sizes_constant=split, index=0),
                runtime_node("r5", "split_get", ["r3"], dim=-1, sizes_constant=split, index=1),
                runtime_node("r6", "sparse_mm", ["r1", "r4"]),
                runtime_node("r7", "add", ["r6", "r5"]),
            ],
            "outputs": ["r7"],
        }
        result.append(plan([parameter_node("d0", "cat", [weight, skip_weight], dim=1)], packed))
    return result


def fold_conv_batch_norm(payload):
    items, lookup = nodes(payload), by_id(payload)
    if Counter(item["op"] for item in items) != Counter(
        {"parameter": 6, "input": 1, "conv2d": 1, "batch_norm_eval": 1}
    ):
        return None
    conv, bn = only(items, "conv2d"), only(items, "batch_norm_eval")
    if conv is None or bn is None or bn["args"][0] != conv["id"]:
        return None
    x = lookup[conv["args"][0]]
    values = [lookup[item] for item in conv["args"][1:] + bn["args"][1:]]
    names = [value_name(x, "input")] + [value_name(item, "parameter") for item in values]
    if any(item is None for item in names) or len(names) != 7:
        return None
    input_name, weight, bias, gamma, beta, mean, variance = names
    scale_shape = next(
        (
            name
            for name, value in payload["constants"].items()
            if isinstance(value, list) and len(value) == 4 and value[1:] == [1, 1, 1]
        ),
        None,
    )
    if scale_shape is None:
        return None
    derived = [
        parameter_node("d0", "rsqrt_add_scalar", [variance], scalar_constant=bn["attrs"]["epsilon_constant"]),
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
    return plan(derived, program)


def stencil_convolution(payload):
    items = nodes(payload)
    counts = Counter(item["op"] for item in items)
    if counts["roll"] != 4 or counts["conv2d"] or counts["mul"] != 2:
        return None
    input_node = only(items, "input")
    center = next((name for name, value in payload["constants"].items() if value == 0.96), None)
    neighbor = next((name for name, value in payload["constants"].items() if value == 0.01), None)
    if input_node is None or center is None or neighbor is None:
        return None
    program = {
        "nodes": [
            runtime_node("r0", "input", name=value_name(input_node, "input")),
            runtime_node("r1", "parameter", name="d0"),
            runtime_node("r2", "pad_circular", ["r0"], padding=[1, 1, 1, 1]),
            runtime_node("r3", "conv2d", ["r2", "r1"], stride=[1, 1], padding=[0, 0], dilation=[1, 1], groups=1),
        ],
        "outputs": ["r3"],
    }
    return plan(
        [parameter_node("d0", "stencil_kernel", center_constant=center, neighbor_constant=neighbor)],
        program,
    )


def primitive_layer_norm(payload):
    items = nodes(payload)
    counts = Counter(item["op"] for item in items)
    if counts["reduce_mean"] != 2 or counts["rsqrt"] != 1 or counts["layer_norm"]:
        return None
    input_node = only(items, "input")
    parameters = [item for item in items if item["op"] == "parameter"]
    types = {item["name"]: item["type"] for item in payload["parameters"]}
    wide = [
        item
        for item in parameters
        if tuple(types[value_name(item, "parameter")]["shape"]) != (1,)
    ]
    normalized = next(
        (name for name, value in payload["constants"].items() if isinstance(value, list) and len(value) == 1),
        None,
    )
    epsilon = next(
        (name for name, value in payload["constants"].items() if type(value) is float and 0 < value < 0.01),
        None,
    )
    if input_node is None or len(wide) != 2 or normalized is None or epsilon is None:
        return None
    gamma, beta = (value_name(item, "parameter") for item in wide)
    program = {
        "nodes": [
            runtime_node("r0", "input", name=value_name(input_node, "input")),
            runtime_node("r1", "parameter", name=gamma),
            runtime_node("r2", "parameter", name=beta),
            runtime_node("r3", "layer_norm", ["r0", "r1", "r2"], normalized_shape_constant=normalized, epsilon_constant=epsilon),
        ],
        "outputs": ["r3"],
    }
    return plan([], program)


def dense_matrix_chain(payload):
    items, lookup = nodes(payload), by_id(payload)
    if Counter(item["op"] for item in items) != Counter(
        {"matmul": 2, "parameter": 2, "input": 1}
    ):
        return []
    output = lookup[payload["reference_program"]["outputs"][0]]
    left = lookup[output["args"][0]] if output["op"] == "matmul" else None
    if left is None or left["op"] != "matmul":
        return []
    a, b = (lookup[item] for item in left["args"])
    c = lookup[output["args"][1]]
    names = (
        value_name(a, "input"),
        value_name(b, "parameter"),
        value_name(c, "parameter"),
    )
    if any(item is None for item in names):
        return []
    input_name, b_name, c_name = names
    right = {
        "nodes": [
            runtime_node("r0", "input", name=input_name),
            runtime_node("r1", "parameter", name=b_name),
            runtime_node("r2", "parameter", name=c_name),
            runtime_node("r3", "matmul", ["r1", "r2"]),
            runtime_node("r4", "matmul", ["r0", "r3"]),
        ],
        "outputs": ["r4"],
    }
    composed = {
        "nodes": [
            runtime_node("r0", "input", name=input_name),
            runtime_node("r1", "parameter", name="d0"),
            runtime_node("r2", "matmul", ["r0", "r1"]),
        ],
        "outputs": ["r2"],
    }
    return [
        plan([], right),
        plan([parameter_node("d0", "matmul", [b_name, c_name])], composed),
    ]


def enumerate_plans(payload):
    choices = [reference_plan(payload)]
    alternatives = [
        mamba_composition(payload),
        *graph_reassociations(payload),
        fold_conv_batch_norm(payload),
        stencil_convolution(payload),
        primitive_layer_norm(payload),
        *dense_matrix_chain(payload),
    ]
    choices.extend(item for item in alternatives if item is not None)
    unique = {}
    for item in choices:
        unique.setdefault(canonical_json(item), item)
    return list(unique.values())


def structural_signature(payload):
    items = nodes(payload)
    positions = {item["id"]: index for index, item in enumerate(items)}
    result = []
    for item in items:
        attrs = {}
        for key, value in item["attrs"].items():
            if key == "name":
                continue
            if key.endswith("_constant") and isinstance(value, str):
                constant = payload["constants"][value]
                attrs[key] = {
                    "constant_type": type(constant).__name__,
                    "list_length": len(constant) if isinstance(constant, list) else None,
                }
            else:
                attrs[key] = value
        result.append(
            {"op": item["op"], "args": [positions[arg] for arg in item["args"]], "attrs": attrs}
        )
    return canonical_json(result)


def features(payload):
    counts = Counter(item["op"] for item in nodes(payload))
    def elements(items):
        return sum(math.prod(spec["type"]["shape"]) for spec in items)
    input_last_dim = payload["inputs"][0]["type"]["shape"][-1]
    output_last_dim = payload["outputs"][0]["type"]["shape"][-1]
    association_flop_delta = 0
    if counts == Counter({"parameter": 2, "matmul": 2, "input": 1}):
        rows, inner_left = payload["inputs"][0]["type"]["shape"]
        inner_right = payload["parameters"][0]["type"]["shape"][1]
        columns = payload["outputs"][0]["type"]["shape"][1]
        left_flops = rows * inner_left * inner_right + rows * inner_right * columns
        right_flops = inner_left * inner_right * columns + rows * inner_left * columns
        association_flop_delta = left_flops - right_flops
    elif counts == Counter(
        {"parameter": 3, "matmul": 2, "input": 1, "sparse_mm": 1, "add": 1}
    ):
        association_flop_delta = input_last_dim - output_last_dim
    return {
        "input_count": len(payload["inputs"]),
        "parameter_count": len(payload["parameters"]),
        "node_count": len(nodes(payload)),
        "reuse_calls": payload["reuse_calls"],
        "input_elements": elements(payload["inputs"]),
        "parameter_elements": elements(payload["parameters"]),
        "input_last_dim": input_last_dim,
        "output_last_dim": output_last_dim,
        "width_delta": input_last_dim - output_last_dim,
        "association_flop_delta": association_flop_delta,
        "association_right_cheaper": int(association_flop_delta > 0),
        "matmul_count": counts["matmul"] + counts["linear"] + counts["sparse_mm"],
        "conv_count": counts["conv2d"],
        "reduction_count": counts["reduce_mean"],
        "normalization_count": counts["batch_norm_eval"] + counts["layer_norm"],
        "layout_count": counts["reshape"] + counts["permute"],
        "sparse_count": counts["sparse_mm"],
    }


def tree_choice(tree, values):
    while tree["kind"] == "branch":
        tree = tree["left"] if values[tree["feature"]] <= tree["threshold"] else tree["right"]
    if tree["kind"] != "leaf" or type(tree["plan_index"]) is not int:
        raise ValueError("grammar tree is invalid")
    return tree["plan_index"]


def construct(payload, grammar):
    if payload.get("version") != ARTIFACT_VERSION:
        raise ValueError("artifact version mismatch")
    if grammar.get("version") != GRAMMAR_VERSION:
        raise ValueError("grammar version mismatch")
    signature = hashlib.sha256(structural_signature(payload).encode()).hexdigest()
    tree = grammar["rules"].get(signature, {"kind": "leaf", "plan_index": 0})
    choices = enumerate_plans(payload)
    index = tree_choice(tree, features(payload))
    if not 0 <= index < len(choices):
        index = 0
    return choices[index]


def main(argv: Sequence[str] | None = None):
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact", type=pathlib.Path)
    parser.add_argument("grammar", type=pathlib.Path)
    args = parser.parse_args(argv)
    try:
        payload = json.loads(args.artifact.read_text(encoding="utf-8"))
        grammar = json.loads(args.grammar.read_text(encoding="utf-8"))
        print(canonical_json(construct(payload, grammar)))
    except Exception as exc:
        print(f"GHOST_OPERATOR_CANDIDATE_V5 REJECT {exc}", file=sys.stderr)
        raise SystemExit(1) from exc


if __name__ == "__main__":
    main()
