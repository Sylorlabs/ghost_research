#!/usr/bin/env python3
"""Independent connected-subset enumerator for A1 reachability."""

from __future__ import annotations

from torch.fx import Graph, Node


def enumerate_connected(
    graph: Graph, mapping: dict[str, list[object]], maximum: int = 6
) -> dict[int, set[frozenset[str]]]:
    eligible = [
        node
        for node in graph.nodes
        if node.op == "call_function"
        and str(node.target) in mapping
        and mapping[str(node.target)][1] is not None
    ]
    names = {node.name: node for node in eligible}
    adjacency = {node.name: set() for node in eligible}
    for node in eligible:
        for parent in node.all_input_nodes:
            if parent.name in names:
                adjacency[node.name].add(parent.name)
                adjacency[parent.name].add(node.name)
    levels: dict[int, set[frozenset[str]]] = {
        1: {frozenset({name}) for name in names}
    }
    for size in range(2, maximum + 1):
        current: set[frozenset[str]] = set()
        for prior in levels[size - 1]:
            frontier = set().union(*(adjacency[name] for name in prior)) - set(prior)
            for name in frontier:
                current.add(prior | {name})
        levels[size] = current
    return levels
