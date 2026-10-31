#!/usr/bin/env python3
"""Strict parser, interpreter, and motif enumerator for typed-DAG artifacts."""

from __future__ import annotations

import hashlib
import json
import math
from typing import Any


OPS = {"add": 2, "mul": 2, "relu": 1}
TYPE_FIELDS = {"rank", "dtype", "layout", "shape"}


class TypedDagReject(ValueError):
    pass


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def exact(value: dict, fields: set[str], label: str) -> None:
    if set(value) != fields:
        raise TypedDagReject(f"{label} fields mismatch")


def parse_type(value: Any) -> dict:
    if not isinstance(value, dict):
        raise TypedDagReject("type must be object")
    exact(value, TYPE_FIELDS, "type")
    if (
        value["rank"] != 1
        or value["dtype"] != "float64"
        or value["layout"] != "strided"
        or value["shape"] != [4]
    ):
        raise TypedDagReject("unsupported type")
    return value


def parse(raw: bytes) -> dict:
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise TypedDagReject("artifact must be object")
    exact(
        value,
        {
            "version",
            "artifact_id",
            "family",
            "repository",
            "semantic_domain",
            "inputs",
            "nodes",
            "outputs",
            "invocations",
        },
        "artifact",
    )
    if value["version"] != "FOUNDRY_TYPED_DAG_ARTIFACT_V1":
        raise TypedDagReject("version mismatch")
    for field in (
        "artifact_id",
        "family",
        "repository",
        "semantic_domain",
    ):
        if not isinstance(value[field], str) or not value[field]:
            raise TypedDagReject(f"{field} malformed")
    if not isinstance(value["inputs"], list) or not value["inputs"]:
        raise TypedDagReject("inputs malformed")
    symbols: dict[str, dict] = {}
    input_ids = []
    for row in value["inputs"]:
        if not isinstance(row, dict):
            raise TypedDagReject("input malformed")
        exact(row, {"id", "type"}, "input")
        if not isinstance(row["id"], str) or row["id"] in symbols:
            raise TypedDagReject("input id malformed")
        symbols[row["id"]] = parse_type(row["type"])
        input_ids.append(row["id"])
    if not isinstance(value["nodes"], list) or not value["nodes"]:
        raise TypedDagReject("nodes malformed")
    node_ids = []
    for row in value["nodes"]:
        if not isinstance(row, dict):
            raise TypedDagReject("node malformed")
        exact(row, {"id", "op", "args", "type"}, "node")
        if not isinstance(row["id"], str) or row["id"] in symbols:
            raise TypedDagReject("node id malformed")
        if row["op"] not in OPS:
            raise TypedDagReject("unknown operation")
        if (
            not isinstance(row["args"], list)
            or len(row["args"]) != OPS[row["op"]]
            or any(arg not in symbols for arg in row["args"])
        ):
            raise TypedDagReject("node args malformed or cyclic")
        result_type = parse_type(row["type"])
        if any(symbols[arg] != result_type for arg in row["args"]):
            raise TypedDagReject("node type mismatch")
        symbols[row["id"]] = result_type
        node_ids.append(row["id"])
    if (
        not isinstance(value["outputs"], list)
        or not value["outputs"]
        or any(output not in node_ids for output in value["outputs"])
    ):
        raise TypedDagReject("outputs malformed")
    if not isinstance(value["invocations"], list) or len(
        value["invocations"]
    ) != 3:
        raise TypedDagReject("exactly three invocations required")
    for ordinal, row in enumerate(value["invocations"], 1):
        if not isinstance(row, dict):
            raise TypedDagReject("invocation malformed")
        exact(
            row, {"ordinal", "inputs", "expected_outputs"}, "invocation"
        )
        if row["ordinal"] != ordinal or set(row["inputs"]) != set(input_ids):
            raise TypedDagReject("invocation identity malformed")
        for input_id in input_ids:
            vector(row["inputs"][input_id])
        if (
            not isinstance(row["expected_outputs"], list)
            or len(row["expected_outputs"]) != len(value["outputs"])
        ):
            raise TypedDagReject("expected outputs malformed")
        for output in row["expected_outputs"]:
            vector(output)
    return value


def vector(value: Any) -> list[float]:
    if (
        not isinstance(value, list)
        or len(value) != 4
        or any(
            not isinstance(item, (int, float))
            or isinstance(item, bool)
            or not math.isfinite(item)
            for item in value
        )
    ):
        raise TypedDagReject("vector malformed")
    return [float(item) for item in value]


def apply(op: str, args: list[list[float]]) -> list[float]:
    if op == "add":
        return [left + right for left, right in zip(args[0], args[1])]
    if op == "mul":
        return [left * right for left, right in zip(args[0], args[1])]
    if op == "relu":
        return [max(0.0, item) for item in args[0]]
    raise TypedDagReject("unknown operation")


def execute(artifact: dict, invocation: dict) -> list[list[float]]:
    values = {
        key: vector(value) for key, value in invocation["inputs"].items()
    }
    for node in artifact["nodes"]:
        values[node["id"]] = apply(
            node["op"], [values[arg] for arg in node["args"]]
        )
    return [values[output] for output in artifact["outputs"]]


def max_error(left: list[list[float]], right: list[list[float]]) -> float:
    return max(
        abs(a - b)
        for left_vector, right_vector in zip(left, right)
        for a, b in zip(left_vector, right_vector)
    )


def body(artifact: dict, path: list[str]) -> dict:
    by_id = {node["id"]: node for node in artifact["nodes"]}
    return {
        "nodes": [
            {
                "op": by_id[node_id]["op"],
                "arity": len(by_id[node_id]["args"]),
                "type": by_id[node_id]["type"],
            }
            for node_id in path
        ]
    }


def enumerate_groups(artifact: dict) -> tuple[list[dict], int]:
    node_ids = [node["id"] for node in artifact["nodes"]]
    users = {node_id: [] for node_id in node_ids}
    for node in artifact["nodes"]:
        for arg in node["args"]:
            if arg in users:
                users[arg].append(node["id"])
    groups: dict[str, dict] = {}
    path_count = 0

    def extend(path: list[str], target_length: int) -> None:
        nonlocal path_count
        if len(path) == target_length:
            path_count += 1
            motif = body(artifact, path)
            identity = hashlib.sha256(canonical(motif)).hexdigest()
            row = groups.setdefault(
                identity,
                {"tool_sha256": identity, "body": motif, "occurrences": []},
            )
            row["occurrences"].append(list(path))
            return
        for user in sorted(users[path[-1]]):
            if user not in path:
                extend(path + [user], target_length)

    for length in (2, 3):
        for node_id in node_ids:
            extend([node_id], length)
    rows = []
    for identity, row in sorted(groups.items()):
        structural_units = len(row["body"]["nodes"])
        occurrence_count = len(row["occurrences"])
        raw_cost = structural_units * occurrence_count
        tool_cost = structural_units + occurrence_count
        rows.append(
            {
                **row,
                "occurrence_count": occurrence_count,
                "structural_units": structural_units,
                "description_length_gain": raw_cost - tool_cost,
            }
        )
    return rows, path_count


def select(groups: list[dict], arm_id: str) -> list[dict]:
    if arm_id == "A3":
        rows = [
            row
            for row in groups
            if row["occurrence_count"] >= 2
            and row["description_length_gain"] > 0
        ]
        return sorted(
            rows,
            key=lambda row: (
                -row["description_length_gain"],
                -row["occurrence_count"],
                row["structural_units"],
                row["tool_sha256"],
            ),
        )
    if arm_id != "A9":
        raise TypedDagReject("state-reset adapter supports only A3/A9")
    selected = []
    covered: set[str] = set()
    remaining = {row["tool_sha256"]: row for row in groups}
    while remaining:
        ranking = []
        for row in remaining.values():
            nodes = {
                node
                for occurrence in row["occurrences"]
                for node in occurrence
            }
            marginal = len(nodes - covered)
            ranking.append(
                (
                    -(marginal / row["structural_units"]),
                    -marginal,
                    row["structural_units"],
                    row["tool_sha256"],
                    nodes,
                    row,
                )
            )
        ranking.sort(key=lambda item: item[:4])
        _, negative_marginal, _, identity, nodes, row = ranking[0]
        if -negative_marginal == 0:
            break
        selected.append(row)
        covered.update(nodes)
        del remaining[identity]
    return selected


def covered_nodes(selected: list[dict]) -> set[str]:
    return {
        node
        for row in selected
        for occurrence in row["occurrences"]
        for node in occurrence
    }
