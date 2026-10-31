#!/usr/bin/env python3
"""Independent A6 typed extractor, anti-unifier, matcher, and validator."""

from __future__ import annotations

import json
import math
from typing import Any

import torch
from torch.fx import GraphModule, Node


class IndependentA6Reject(ValueError):
    pass


def encode(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def describe_type(value: Any) -> dict[str, Any]:
    if torch.is_tensor(value):
        return {
            "kind": "tensor",
            "dtype": str(value.dtype),
            "rank": len(value.shape),
        }
    if isinstance(value, tuple):
        return {
            "kind": "tuple",
            "items": [describe_type(item) for item in value],
        }
    if isinstance(value, list):
        return {
            "kind": "list",
            "items": [describe_type(item) for item in value],
        }
    if value is None or type(value) in (bool, int, float, str):
        return {"kind": "scalar", "type": type(value).__name__}
    return {"kind": "opaque", "type": type(value).__name__}


def atom(value: Any) -> Any:
    if value is None or type(value) in (bool, int, str):
        return value
    if type(value) is float:
        if math.isnan(value) or math.isinf(value):
            raise IndependentA6Reject("bad float")
        return value
    if isinstance(value, torch.dtype):
        return {"torch_dtype": str(value)}
    if isinstance(value, torch.device):
        return {"torch_device": str(value)}
    if isinstance(value, slice):
        return {"slice": [atom(value.start), atom(value.stop), atom(value.step)]}
    return {"typed_repr": [value.__class__.__name__, str(value)]}


def build(value: Any, remaining: int) -> dict[str, Any]:
    if isinstance(value, Node):
        typ = describe_type(value.meta.get("val"))
        if value.op == "call_function" and remaining:
            positional = [build(item, remaining - 1) for item in value.args]
            named = [
                [str(key), build(item, remaining - 1)]
                for key, item in sorted(value.kwargs.items(), key=lambda row: str(row[0]))
            ]
            return {
                "kind": "op",
                "type": typ,
                "target": str(value.target),
                "args": positional,
                "kwargs": named,
            }
        category = "cutoff_call_function" if value.op == "call_function" else value.op
        return {
            "kind": "boundary",
            "type": typ,
            "boundary": category,
            "identity": str(value.target),
        }
    if isinstance(value, (tuple, list)):
        return {
            "kind": "tuple" if isinstance(value, tuple) else "list",
            "type": describe_type(value),
            "items": [build(item, remaining) for item in value],
        }
    return {
        "kind": "literal",
        "type": describe_type(value),
        "value": atom(value),
    }


def extract(
    module: GraphModule, artifact_id: str, depth: int
) -> list[dict[str, Any]]:
    output = []
    for item in module.graph.nodes:
        if item.op == "call_function":
            output.append(
                {
                    "root_id": artifact_id + ":" + item.name,
                    "artifact_id": artifact_id,
                    "node_name": item.name,
                    "term": build(item, depth),
                }
            )
    return output


def generalize(a: dict[str, Any], b: dict[str, Any]) -> dict[str, Any]:
    pair_ids: dict[tuple[str, str], int] = {}

    def go(left: dict[str, Any], right: dict[str, Any]) -> dict[str, Any]:
        if left.get("type") != right.get("type"):
            raise IndependentA6Reject("incompatible types")
        if encode(left) == encode(right):
            return json.loads(encode(left))
        same_op = (
            left.get("kind") == right.get("kind") == "op"
            and left.get("target") == right.get("target")
            and len(left.get("args", ())) == len(right.get("args", ()))
            and tuple(x[0] for x in left.get("kwargs", ()))
            == tuple(x[0] for x in right.get("kwargs", ()))
        )
        if same_op:
            return {
                "kind": "op",
                "type": left["type"],
                "target": left["target"],
                "args": [
                    go(x, y)
                    for x, y in zip(left["args"], right["args"], strict=True)
                ],
                "kwargs": [
                    [x[0], go(x[1], y[1])]
                    for x, y in zip(
                        left["kwargs"], right["kwargs"], strict=True
                    )
                ],
            }
        same_container = (
            left.get("kind") == right.get("kind")
            and left.get("kind") in ("tuple", "list")
            and len(left.get("items", ())) == len(right.get("items", ()))
        )
        if same_container:
            return {
                "kind": left["kind"],
                "type": left["type"],
                "items": [
                    go(x, y)
                    for x, y in zip(
                        left["items"], right["items"], strict=True
                    )
                ],
            }
        pair = tuple(sorted((encode(left), encode(right))))
        if pair not in pair_ids:
            pair_ids[pair] = len(pair_ids)
        return {
            "kind": "hole",
            "type": left["type"],
            "temporary": pair_ids[pair],
        }

    raw = go(a, b)
    encountered: dict[int, str] = {}

    def rename(node: dict[str, Any]) -> dict[str, Any]:
        kind = node["kind"]
        if kind == "hole":
            old = node["temporary"]
            if old not in encountered:
                encountered[old] = "?" + str(len(encountered))
            return {
                "kind": "hole",
                "type": node["type"],
                "name": encountered[old],
            }
        if kind == "op":
            return {
                "kind": "op",
                "type": node["type"],
                "target": node["target"],
                "args": [rename(x) for x in node["args"]],
                "kwargs": [[key, rename(x)] for key, x in node["kwargs"]],
            }
        if kind in ("tuple", "list"):
            return {
                "kind": kind,
                "type": node["type"],
                "items": [rename(x) for x in node["items"]],
            }
        return json.loads(encode(node))

    return rename(raw)


def metrics(pattern: dict[str, Any]) -> tuple[int, int]:
    ops = 0
    names: set[str] = set()
    pending = [pattern]
    while pending:
        item = pending.pop()
        if item["kind"] == "op":
            ops += 1
            pending.extend(reversed(item["args"]))
            pending.extend(reversed([value for _, value in item["kwargs"]]))
        elif item["kind"] in ("tuple", "list"):
            pending.extend(reversed(item["items"]))
        elif item["kind"] == "hole":
            names.add(item["name"])
    return ops, len(names)


def accepts(pattern: dict[str, Any], concrete: dict[str, Any]) -> bool:
    assigned: dict[str, str] = {}

    def walk(pat: dict[str, Any], value: dict[str, Any]) -> bool:
        if pat.get("type") != value.get("type"):
            return False
        if pat["kind"] == "hole":
            serialized = encode(value)
            old = assigned.setdefault(pat["name"], serialized)
            return old == serialized
        if pat["kind"] != value.get("kind"):
            return False
        if pat["kind"] == "op":
            if (
                pat["target"] != value.get("target")
                or len(pat["args"]) != len(value.get("args", ()))
                or [x[0] for x in pat["kwargs"]]
                != [x[0] for x in value.get("kwargs", ())]
            ):
                return False
            return all(
                walk(x, y)
                for x, y in zip(pat["args"], value["args"], strict=True)
            ) and all(
                walk(x[1], y[1])
                for x, y in zip(
                    pat["kwargs"], value["kwargs"], strict=True
                )
            )
        if pat["kind"] in ("tuple", "list"):
            if len(pat["items"]) != len(value.get("items", ())):
                return False
            return all(
                walk(x, y)
                for x, y in zip(
                    pat["items"], value["items"], strict=True
                )
            )
        return encode(pat) == encode(value)

    return walk(pattern, concrete)


def verify_record(
    record: dict[str, Any],
    roots: dict[str, dict[str, Any]],
    minimum_operators: int,
    minimum_holes: int,
    minimum_matches: int,
    minimum_artifacts: int,
) -> None:
    if sorted(record) != ["matches", "pattern", "source_pair"]:
        raise IndependentA6Reject("fields")
    pair = record["source_pair"]
    if (
        type(pair) is not list
        or len(pair) != 2
        or pair[0] == pair[1]
        or pair[0] not in roots
        or pair[1] not in roots
    ):
        raise IndependentA6Reject("pair")
    one, two = roots[pair[0]]["term"], roots[pair[1]]["term"]
    if encode(one) == encode(two):
        raise IndependentA6Reject("duplicate source")
    if encode(record["pattern"]) != encode(generalize(one, two)):
        raise IndependentA6Reject("generalization")
    ops, holes = metrics(record["pattern"])
    if ops < minimum_operators or holes < minimum_holes:
        raise IndependentA6Reject("trivial")
    actual = sorted(
        key for key, row in roots.items() if accepts(record["pattern"], row["term"])
    )
    if record["matches"] != actual or len(actual) < minimum_matches:
        raise IndependentA6Reject("matches")
    if len({roots[key]["artifact_id"] for key in actual}) < minimum_artifacts:
        raise IndependentA6Reject("artifacts")
