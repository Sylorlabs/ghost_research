#!/usr/bin/env python3
"""Primary typed term extraction and Babble-style anti-unification for A6."""

from __future__ import annotations

import hashlib
import json
import math
from typing import Any

import torch
from torch.fx import GraphModule, Node


class A6Reject(ValueError):
    pass


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def value_type(value: Any) -> dict[str, Any]:
    if isinstance(value, torch.Tensor):
        return {
            "kind": "tensor",
            "dtype": str(value.dtype),
            "rank": value.dim(),
        }
    if isinstance(value, tuple):
        return {
            "kind": "tuple",
            "items": [value_type(item) for item in value],
        }
    if isinstance(value, list):
        return {
            "kind": "list",
            "items": [value_type(item) for item in value],
        }
    if value is None or type(value) in {bool, int, float, str}:
        return {"kind": "scalar", "type": type(value).__name__}
    return {"kind": "opaque", "type": type(value).__name__}


def literal_value(value: Any) -> Any:
    if value is None or type(value) in {bool, int, str}:
        return value
    if type(value) is float:
        if not math.isfinite(value):
            raise A6Reject("nonfinite literal")
        return value
    if isinstance(value, torch.dtype):
        return {"torch_dtype": str(value)}
    if isinstance(value, torch.device):
        return {"torch_device": str(value)}
    if isinstance(value, slice):
        return {
            "slice": [
                literal_value(value.start),
                literal_value(value.stop),
                literal_value(value.step),
            ]
        }
    return {"typed_repr": [type(value).__name__, str(value)]}


def node_type(node: Node) -> dict[str, Any]:
    return value_type(node.meta.get("val"))


def extract_value(value: Any, depth: int) -> dict[str, Any]:
    if isinstance(value, Node):
        result_type = node_type(value)
        if value.op == "call_function" and depth > 0:
            return {
                "kind": "op",
                "type": result_type,
                "target": str(value.target),
                "args": [
                    extract_value(item, depth - 1) for item in value.args
                ],
                "kwargs": [
                    [str(key), extract_value(value.kwargs[key], depth - 1)]
                    for key in sorted(value.kwargs, key=str)
                ],
            }
        return {
            "kind": "boundary",
            "type": result_type,
            "boundary": (
                "cutoff_call_function"
                if value.op == "call_function"
                else value.op
            ),
            "identity": str(value.target),
        }
    if isinstance(value, tuple):
        return {
            "kind": "tuple",
            "type": value_type(value),
            "items": [extract_value(item, depth) for item in value],
        }
    if isinstance(value, list):
        return {
            "kind": "list",
            "type": value_type(value),
            "items": [extract_value(item, depth) for item in value],
        }
    return {
        "kind": "literal",
        "type": value_type(value),
        "value": literal_value(value),
    }


def extract_roots(
    module: GraphModule, artifact_id: str, maximum_depth: int
) -> list[dict[str, Any]]:
    roots = []
    for node in module.graph.nodes:
        if node.op != "call_function":
            continue
        term = extract_value(node, maximum_depth)
        roots.append(
            {
                "root_id": f"{artifact_id}:{node.name}",
                "artifact_id": artifact_id,
                "node_name": node.name,
                "term": term,
            }
        )
    return roots


def _pair_key(left: dict[str, Any], right: dict[str, Any]) -> str:
    values = sorted((canonical(left), canonical(right)))
    return hashlib.sha256(("\0".join(values)).encode()).hexdigest()


def anti_unify(
    left: dict[str, Any], right: dict[str, Any]
) -> dict[str, Any]:
    state_holes: dict[str, str] = {}

    def visit(a: dict[str, Any], b: dict[str, Any]) -> dict[str, Any]:
        if a.get("type") != b.get("type"):
            raise A6Reject("type-incompatible pair state")
        if a == b:
            return json.loads(canonical(a))
        if (
            a.get("kind") == b.get("kind") == "op"
            and a.get("target") == b.get("target")
            and len(a.get("args", [])) == len(b.get("args", []))
            and [row[0] for row in a.get("kwargs", [])]
            == [row[0] for row in b.get("kwargs", [])]
        ):
            return {
                "kind": "op",
                "type": a["type"],
                "target": a["target"],
                "args": [
                    visit(x, y)
                    for x, y in zip(a["args"], b["args"], strict=True)
                ],
                "kwargs": [
                    [x[0], visit(x[1], y[1])]
                    for x, y in zip(
                        a["kwargs"], b["kwargs"], strict=True
                    )
                ],
            }
        if (
            a.get("kind") == b.get("kind")
            and a.get("kind") in {"tuple", "list"}
            and len(a.get("items", [])) == len(b.get("items", []))
        ):
            return {
                "kind": a["kind"],
                "type": a["type"],
                "items": [
                    visit(x, y)
                    for x, y in zip(
                        a["items"], b["items"], strict=True
                    )
                ],
            }
        key = _pair_key(a, b)
        state_holes.setdefault(key, key)
        return {"kind": "hole", "type": a["type"], "state": key}

    raw = visit(left, right)
    normalized: dict[str, str] = {}

    def normalize(term: dict[str, Any]) -> dict[str, Any]:
        kind = term["kind"]
        if kind == "hole":
            state = term["state"]
            normalized.setdefault(state, f"?{len(normalized)}")
            return {
                "kind": "hole",
                "type": term["type"],
                "name": normalized[state],
            }
        if kind == "op":
            return {
                "kind": "op",
                "type": term["type"],
                "target": term["target"],
                "args": [normalize(item) for item in term["args"]],
                "kwargs": [
                    [key, normalize(value)]
                    for key, value in term["kwargs"]
                ],
            }
        if kind in {"tuple", "list"}:
            return {
                "kind": kind,
                "type": term["type"],
                "items": [normalize(item) for item in term["items"]],
            }
        return json.loads(canonical(term))

    return normalize(raw)


def statistics(pattern: dict[str, Any]) -> dict[str, int]:
    operators = 0
    holes: set[str] = set()

    def visit(term: dict[str, Any]) -> None:
        nonlocal operators
        if term["kind"] == "op":
            operators += 1
            for item in term["args"]:
                visit(item)
            for _, item in term["kwargs"]:
                visit(item)
        elif term["kind"] in {"tuple", "list"}:
            for item in term["items"]:
                visit(item)
        elif term["kind"] == "hole":
            holes.add(term["name"])

    visit(pattern)
    return {"operator_nodes": operators, "distinct_metavariables": len(holes)}


def matches(pattern: dict[str, Any], term: dict[str, Any]) -> bool:
    bindings: dict[str, dict[str, Any]] = {}

    def visit(pat: dict[str, Any], concrete: dict[str, Any]) -> bool:
        if pat.get("type") != concrete.get("type"):
            return False
        if pat["kind"] == "hole":
            name = pat["name"]
            if name in bindings:
                return bindings[name] == concrete
            bindings[name] = concrete
            return True
        if pat["kind"] != concrete.get("kind"):
            return False
        if pat["kind"] == "op":
            return (
                pat["target"] == concrete.get("target")
                and len(pat["args"]) == len(concrete.get("args", []))
                and [row[0] for row in pat["kwargs"]]
                == [row[0] for row in concrete.get("kwargs", [])]
                and all(
                    visit(x, y)
                    for x, y in zip(
                        pat["args"], concrete["args"], strict=True
                    )
                )
                and all(
                    visit(x[1], y[1])
                    for x, y in zip(
                        pat["kwargs"], concrete["kwargs"], strict=True
                    )
                )
            )
        if pat["kind"] in {"tuple", "list"}:
            return len(pat["items"]) == len(
                concrete.get("items", [])
            ) and all(
                visit(x, y)
                for x, y in zip(
                    pat["items"], concrete["items"], strict=True
                )
            )
        return pat == concrete

    return visit(pattern, term)


def validate_record(
    record: dict[str, Any],
    universe: dict[str, dict[str, Any]],
    *,
    minimum_operators: int,
    minimum_holes: int,
    minimum_matches: int,
    minimum_artifacts: int,
) -> None:
    if set(record) != {"pattern", "source_pair", "matches"}:
        raise A6Reject("record fields")
    pair = record["source_pair"]
    if (
        not isinstance(pair, list)
        or len(pair) != 2
        or pair[0] == pair[1]
        or any(item not in universe for item in pair)
    ):
        raise A6Reject("source pair")
    left, right = (universe[item]["term"] for item in pair)
    if left == right:
        raise A6Reject("byte-identical source pair")
    expected_pattern = anti_unify(left, right)
    if record["pattern"] != expected_pattern:
        raise A6Reject("pattern is not canonical source anti-unification")
    stats = statistics(record["pattern"])
    if (
        stats["operator_nodes"] < minimum_operators
        or stats["distinct_metavariables"] < minimum_holes
    ):
        raise A6Reject("trivial candidate")
    expected_matches = sorted(
        root_id
        for root_id, row in universe.items()
        if matches(record["pattern"], row["term"])
    )
    if record["matches"] != expected_matches:
        raise A6Reject("match set mismatch")
    if len(expected_matches) < minimum_matches:
        raise A6Reject("insufficient matches")
    artifacts = {universe[item]["artifact_id"] for item in expected_matches}
    if len(artifacts) < minimum_artifacts:
        raise A6Reject("insufficient matching artifacts")
