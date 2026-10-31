#!/usr/bin/env python3
"""Independent typed-DAG execution and state-reset motif verification."""

from __future__ import annotations

import hashlib
import json
import math
from typing import Any


class IndependentStateResetReject(ValueError):
    pass


def parse_and_run(raw: bytes, arm_id: str) -> dict[str, Any]:
    artifact = json.loads(raw)
    if set(artifact) != {
        "version",
        "artifact_id",
        "family",
        "repository",
        "semantic_domain",
        "inputs",
        "nodes",
        "outputs",
        "invocations",
    }:
        raise IndependentStateResetReject("artifact fields")
    if artifact.get("version") != "FOUNDRY_TYPED_DAG_ARTIFACT_V1":
        raise IndependentStateResetReject("version")
    if arm_id not in {"A3", "A9"}:
        raise IndependentStateResetReject("arm")
    if len(artifact.get("invocations", [])) != 3:
        raise IndependentStateResetReject("invocations")
    known = {row["id"] for row in artifact["inputs"]}
    node_map = {}
    consumers: dict[str, list[str]] = {}
    for node in artifact["nodes"]:
        if (
            node["op"] not in {"add", "mul", "relu"}
            or node["id"] in known
            or any(arg not in known for arg in node["args"])
            or node["type"]
            != {
                "rank": 1,
                "dtype": "float64",
                "layout": "strided",
                "shape": [4],
            }
        ):
            raise IndependentStateResetReject("graph")
        if len(node["args"]) != (1 if node["op"] == "relu" else 2):
            raise IndependentStateResetReject("arity")
        known.add(node["id"])
        node_map[node["id"]] = node
        consumers.setdefault(node["id"], [])
        for arg in node["args"]:
            consumers.setdefault(arg, []).append(node["id"])
    errors = []
    output_digests = []
    for expected_ordinal, invocation in enumerate(
        artifact["invocations"], 1
    ):
        if invocation["ordinal"] != expected_ordinal:
            raise IndependentStateResetReject("ordinal")
        values = {
            key: [float(item) for item in vector]
            for key, vector in invocation["inputs"].items()
        }
        if set(values) != {row["id"] for row in artifact["inputs"]} or any(
            len(vector) != 4 or not all(map(math.isfinite, vector))
            for vector in values.values()
        ):
            raise IndependentStateResetReject("input vector")
        for node in artifact["nodes"]:
            args = [values[arg] for arg in node["args"]]
            if node["op"] == "add":
                result = [a + b for a, b in zip(args[0], args[1])]
            elif node["op"] == "mul":
                result = [a * b for a, b in zip(args[0], args[1])]
            else:
                result = [item if item > 0 else 0.0 for item in args[0]]
            if len(result) != 4 or not all(map(math.isfinite, result)):
                raise IndependentStateResetReject("execution")
            values[node["id"]] = result
        outputs = [values[key] for key in artifact["outputs"]]
        expected = invocation["expected_outputs"]
        if len(expected) != len(artifact["outputs"]) or any(
            len(vector) != 4 or not all(map(math.isfinite, vector))
            for vector in expected
        ):
            raise IndependentStateResetReject("expected output")
        error = max(
            abs(a - b)
            for actual_row, expected_row in zip(outputs, expected)
            for a, b in zip(actual_row, expected_row)
        )
        errors.append(error)
        output_digests.append(
            hashlib.sha256(
                json.dumps(
                    outputs, sort_keys=True, separators=(",", ":")
                ).encode()
            ).hexdigest()
        )

    paths = []
    for length in (2, 3):
        for start in node_map:
            frontier = [[start]]
            while frontier:
                path = frontier.pop()
                if len(path) == length:
                    paths.append(path)
                    continue
                for child in sorted(consumers.get(path[-1], []), reverse=True):
                    if child not in path:
                        frontier.append(path + [child])
    grouped: dict[str, dict] = {}
    for path in paths:
        signature = tuple(
            (
                node_map[node_id]["op"],
                len(node_map[node_id]["args"]),
                1,
                "float64",
                "strided",
                (4,),
            )
            for node_id in path
        )
        key = hashlib.sha256(repr(signature).encode()).hexdigest()
        grouped.setdefault(
            key,
            {"paths": [], "length": len(path), "signature": signature},
        )["paths"].append(path)
    if arm_id == "A3":
        chosen = [
            row
            for row in grouped.values()
            if len(row["paths"]) >= 2
            and row["length"] * len(row["paths"])
            - (row["length"] + len(row["paths"]))
            > 0
        ]
    else:
        chosen = []
        covered: set[str] = set()
        remaining = list(grouped.values())
        while remaining:
            ranked = []
            for row in remaining:
                nodes = {node for path in row["paths"] for node in path}
                marginal = len(nodes - covered)
                ranked.append(
                    (
                        -(marginal / row["length"]),
                        -marginal,
                        row["length"],
                        repr(row["signature"]),
                        nodes,
                        row,
                    )
                )
            ranked.sort(key=lambda item: item[:4])
            _, negative, _, _, nodes, row = ranked[0]
            if -negative == 0:
                break
            chosen.append(row)
            covered.update(nodes)
            remaining.remove(row)
    covered = {
        node for row in chosen for path in row["paths"] for node in path
    }
    return {
        "invocations": 3,
        "max_abs_error": max(errors),
        "output_digests": output_digests,
        "paths": len(paths),
        "groups": len(grouped),
        "selected": len(chosen),
        "covered_nodes": len(covered),
        "all_selected_repeated_positive_mdl": (
            all(
                len(row["paths"]) >= 2
                and row["length"] * len(row["paths"])
                - (row["length"] + len(row["paths"]))
                > 0
                for row in chosen
            )
            if arm_id == "A3"
            else None
        ),
    }
