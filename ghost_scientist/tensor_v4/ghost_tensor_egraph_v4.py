#!/usr/bin/env python3
"""Evaluator-owned equality saturation for the Tensor v4 partition language.

An e-node is one exact partition of same-input projections into linear groups.
The bidirectional fuse/split equality rewrites connect semantically equivalent
plans.  Saturation starts at the separate-projection term, adds every reachable
term, unions each rewrite result with its source e-class, rebuilds to a
fixpoint, and then extracts the lowest logical-GEMM-cost representative.
"""

from __future__ import annotations

import argparse
import json
from collections.abc import Iterable


Partition = tuple[tuple[int, ...], ...]


def canonical_partition(groups: Iterable[Iterable[int]], count: int) -> Partition:
    normalized = tuple(
        sorted((tuple(sorted(group)) for group in groups), key=lambda group: group[0])
    )
    flat = tuple(index for group in normalized for index in group)
    if (
        any(not group for group in normalized)
        or sorted(flat) != list(range(count))
        or len(set(flat)) != count
    ):
        raise ValueError("partition is not exact")
    return normalized


def identity_partition(count: int) -> Partition:
    return tuple((index,) for index in range(count))


def fuse_rewrites(partition: Partition, count: int) -> set[Partition]:
    outputs: set[Partition] = set()
    for left in range(len(partition)):
        for right in range(left + 1, len(partition)):
            replacement = tuple(
                group
                for index, group in enumerate(partition)
                if index not in (left, right)
            ) + (tuple(sorted(partition[left] + partition[right])),)
            outputs.add(canonical_partition(replacement, count))
    return outputs


def split_rewrites(partition: Partition, count: int) -> set[Partition]:
    outputs: set[Partition] = set()
    for group_index, group in enumerate(partition):
        if len(group) < 2:
            continue
        # Keep group[0] on the left to avoid producing both orientations.
        rest = group[1:]
        for mask in range(1 << len(rest)):
            left = (group[0],) + tuple(
                value for bit, value in enumerate(rest) if mask & (1 << bit)
            )
            right = tuple(
                value for bit, value in enumerate(rest) if not mask & (1 << bit)
            )
            if not right:
                continue
            replacement = (
                partition[:group_index]
                + partition[group_index + 1 :]
                + (left, right)
            )
            outputs.add(canonical_partition(replacement, count))
    return outputs


class EGraph:
    def __init__(self) -> None:
        self.nodes: list[Partition] = []
        self.node_ids: dict[Partition, int] = {}
        self.parent: list[int] = []
        self.rank: list[int] = []
        self.union_count = 0

    def add(self, node: Partition) -> tuple[int, bool]:
        existing = self.node_ids.get(node)
        if existing is not None:
            return existing, False
        node_id = len(self.nodes)
        self.nodes.append(node)
        self.node_ids[node] = node_id
        self.parent.append(node_id)
        self.rank.append(0)
        return node_id, True

    def find(self, node_id: int) -> int:
        parent = self.parent[node_id]
        if parent != node_id:
            self.parent[node_id] = self.find(parent)
        return self.parent[node_id]

    def union(self, left: int, right: int) -> bool:
        left_root = self.find(left)
        right_root = self.find(right)
        if left_root == right_root:
            return False
        if self.rank[left_root] < self.rank[right_root]:
            left_root, right_root = right_root, left_root
        self.parent[right_root] = left_root
        if self.rank[left_root] == self.rank[right_root]:
            self.rank[left_root] += 1
        self.union_count += 1
        return True

    def rebuild(self) -> int:
        roots = {self.find(node_id) for node_id in range(len(self.nodes))}
        return len(roots)


def extraction_cost(partition: Partition) -> tuple[int, int, Partition]:
    logical_gemms = len(partition)
    split_views = sum(len(group) for group in partition if len(group) > 1)
    return logical_gemms, split_views, partition


def saturate(count: int) -> tuple[Partition, dict[str, object]]:
    if not 2 <= count <= 6:
        raise ValueError("projection count is outside the protocol")
    graph = EGraph()
    root_node, _ = graph.add(identity_partition(count))
    iterations = 0
    rewrite_applications = 0
    while True:
        iterations += 1
        added = 0
        snapshot = tuple(graph.nodes)
        for source in snapshot:
            source_id = graph.node_ids[source]
            rewrites = fuse_rewrites(source, count) | split_rewrites(source, count)
            rewrite_applications += len(rewrites)
            for target in sorted(rewrites):
                target_id, was_added = graph.add(target)
                added += int(was_added)
                graph.union(source_id, target_id)
        eclass_count = graph.rebuild()
        if added == 0:
            break
        if iterations > 16:
            raise RuntimeError("equality saturation did not reach a fixpoint")
    root_class = graph.find(root_node)
    equivalents = [
        node
        for node_id, node in enumerate(graph.nodes)
        if graph.find(node_id) == root_class
    ]
    selected = min(equivalents, key=extraction_cost)
    receipt: dict[str, object] = {
        "engine": "GHOST_TENSOR_EGRAPH_V4",
        "start": [list(group) for group in identity_partition(count)],
        "rewrite_rules": ["fuse_parallel_groups", "split_parallel_group"],
        "iterations": iterations,
        "rewrite_applications": rewrite_applications,
        "enode_count": len(graph.nodes),
        "eclass_count": eclass_count,
        "union_count": graph.union_count,
        "fixpoint": True,
        "selected_cost": {
            "logical_gemm_kernels": len(selected),
            "logical_split_views": sum(
                len(group) for group in selected if len(group) > 1
            ),
        },
    }
    return selected, receipt


def selftest() -> None:
    expected_bell = {2: 2, 3: 5, 4: 15, 5: 52, 6: 203}
    for count, expected in expected_bell.items():
        selected, receipt = saturate(count)
        if receipt["enode_count"] != expected:
            raise AssertionError(f"Bell({count}) coverage failed")
        if receipt["eclass_count"] != 1 or selected != (tuple(range(count)),):
            raise AssertionError("e-class union or extraction failed")
    print(
        "GHOST_TENSOR_EGRAPH_V4_SELFTEST PASS"
        " bell_2_through_6=true eclasses=1 fixpoint=true extraction=pack_all"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int)
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()
    if args.selftest:
        selftest()
        return
    if args.count is None:
        parser.error("--count is required")
    selected, receipt = saturate(args.count)
    print(
        json.dumps(
            {
                "status": "GHOST_TENSOR_EGRAPH_V4_PASS",
                "plan": {
                    "version": "GHOST_TENSOR_PLAN_V4",
                    "groups": [list(group) for group in selected],
                },
                "receipt": receipt,
            },
            sort_keys=True,
            separators=(",", ":"),
        )
    )


if __name__ == "__main__":
    main()
