#!/usr/bin/env python3
"""Independent A8 fixed-tool matching and strategy evaluation."""

from __future__ import annotations

from typing import Any

import torch
from torch.fx import Node


class IndependentA8StrategyReject(ValueError):
    pass


def tensor_signature(node: Node) -> tuple[int, str, str] | None:
    value = node.meta.get("val")
    if not torch.is_tensor(value):
        return None
    return len(value.shape), str(value.dtype), str(value.layout)


def discover(graph: Any, portfolio: dict[str, Any]) -> list[dict[str, Any]]:
    calls = [
        item
        for item in graph.nodes
        if item.op == "call_function" and tensor_signature(item) is not None
    ]
    allowed = set(calls)
    found = []
    for spec in portfolio["tools"]:
        signature = (spec["rank"], spec["dtype"], spec["layout"])
        pending = [([node], 0) for node in reversed(calls)]
        while pending:
            path, index = pending.pop()
            tail = path[-1]
            if (
                str(tail.target) != spec["targets"][index]
                or tensor_signature(tail) != signature
            ):
                continue
            if index + 1 == len(spec["targets"]):
                found.append(
                    {
                        "tool": spec["name"],
                        "nodes": [item.name for item in path],
                    }
                )
                continue
            users = [
                item
                for item in tail.users
                if item in allowed and item not in path
            ]
            for user in reversed(sorted(users, key=lambda item: item.name)):
                pending.append((path + [user], index + 1))
    return sorted(found, key=lambda row: (row["tool"], row["nodes"]))


def score(
    order: tuple[str, ...],
    graph_matches: list[tuple[str, list[dict[str, Any]]]],
) -> dict[str, Any]:
    position = dict(zip(order, range(len(order)), strict=True))
    chosen = []
    conflicts = 0
    coverage = set()
    artifacts = set()
    for artifact_id, candidates in graph_matches:
        occupied = set()
        candidates = sorted(
            candidates,
            key=lambda row: (position[row["tool"]], tuple(row["nodes"])),
        )
        for candidate in candidates:
            overlap = any(node in occupied for node in candidate["nodes"])
            if overlap:
                conflicts += 1
            else:
                occupied.update(candidate["nodes"])
                artifacts.add(artifact_id)
                coverage.update(
                    (artifact_id, node) for node in candidate["nodes"]
                )
                chosen.append(
                    {
                        "artifact_id": artifact_id,
                        "tool": candidate["tool"],
                        "nodes": list(candidate["nodes"]),
                    }
                )
    return {
        "order": list(order),
        "unique_covered_nodes": len(coverage),
        "eligible_artifacts": len(artifacts),
        "direct_uses": len(chosen),
        "conflict_skips": conflicts,
        "selected": chosen,
    }


def rank_key(row: dict[str, Any]) -> tuple[Any, ...]:
    return (
        -row["unique_covered_nodes"],
        -row["eligible_artifacts"],
        row["direct_uses"],
        row["conflict_skips"],
        tuple(row["order"]),
    )


def verify(
    record: dict[str, Any],
    names: list[str],
    graph_matches: list[tuple[str, list[dict[str, Any]]]],
) -> None:
    required = {
        "order",
        "unique_covered_nodes",
        "eligible_artifacts",
        "direct_uses",
        "conflict_skips",
        "selected",
    }
    if set(record) != required:
        raise IndependentA8StrategyReject("fields")
    order = record["order"]
    if (
        type(order) is not list
        or len(order) != len(names)
        or set(order) != set(names)
        or len(set(order)) != len(order)
    ):
        raise IndependentA8StrategyReject("permutation")
    if record != score(tuple(order), graph_matches):
        raise IndependentA8StrategyReject("score")
