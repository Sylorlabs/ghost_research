#!/usr/bin/env python3
"""Independent source scanner for the frozen Operator-v5 runtime vocabulary."""

from __future__ import annotations

import re


def runtime_ops(source: str) -> set[str]:
    start = source.index("def infer_runtime_program(")
    end = source.index("\ndef _check_output_contracts(", start)
    body = source[start:end]
    found = set(re.findall(r'op == "([a-z0-9_]+)"', body))
    for group in re.findall(r'op in \((.*?)\)', body, flags=re.DOTALL):
        found.update(re.findall(r'"([a-z0-9_]+)"', group))
    return found


def classify_graph(
    operator_counts: dict[str, int],
    mapping: dict[str, list[object]],
) -> dict:
    classes = {"DIRECT_EXACT": 0, "CONDITIONAL_COMPOSITE": 0, "UNSUPPORTED": 0}
    mapped_runtime: dict[str, int] = {}
    for operator, count in operator_counts.items():
        classification, runtime_op = mapping[operator]
        classes[classification] += count
        if classification == "DIRECT_EXACT":
            mapped_runtime[runtime_op] = mapped_runtime.get(runtime_op, 0) + count
    return {
        "classification_counts": classes,
        "mapped_direct_runtime_histogram": dict(sorted(mapped_runtime.items())),
        "whole_graph_direct": (
            classes["CONDITIONAL_COMPOSITE"] == 0
            and classes["UNSUPPORTED"] == 0
        ),
        "whole_graph_has_no_unsupported": classes["UNSUPPORTED"] == 0,
    }
