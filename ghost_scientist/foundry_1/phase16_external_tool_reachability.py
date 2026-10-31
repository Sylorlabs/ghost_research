#!/usr/bin/env python3
"""Phase 16: fail-closed reachability audit from forged tools to external graphs."""

from __future__ import annotations

import collections
import hashlib
import json
import pathlib
import re

from freeze_external_application_intake import verify
from freeze_tensor_forge_component import verify as verify_tensor
from independent_tensor_tool_evaluator import parse_library_bytes


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


OP_TARGETS = {
    "linear": ("torch.ops.aten.linear.",),
    "split_get": ("torch.ops.aten.split.",),
    "cat": ("torch.ops.aten.cat.",),
    "conv2d": ("torch.ops.aten.conv2d.",),
    "batch_norm_eval": (
        "torch.ops.aten.batch_norm.",
        "torch.ops.aten._native_batch_norm_legit_no_training.",
    ),
    "sparse_mm": ("torch.ops.aten._sparse_mm.", "torch.ops.aten.sparse_mm."),
    "matmul": ("torch.ops.aten.matmul.", "torch.ops.aten.mm.",),
    "add": ("torch.ops.aten.add.",),
    "sub": ("torch.ops.aten.sub.",),
    "mul": ("torch.ops.aten.mul.",),
    "reduce_mean": ("torch.ops.aten.mean.",),
    "rsqrt": ("torch.ops.aten.rsqrt.",),
    "roll": ("torch.ops.aten.roll.",),
}


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def target_counts(graph: str) -> collections.Counter[str]:
    targets = re.findall(r"target=([^\]]+?)\]", graph)
    return collections.Counter(target.strip() for target in targets)


def available_count(counts: collections.Counter[str], source_op: str) -> int:
    prefixes = OP_TARGETS.get(source_op, ())
    return sum(
        count
        for target, count in counts.items()
        if any(target.startswith(prefix) for prefix in prefixes)
    )


def required_ops(tool: dict) -> collections.Counter[str]:
    return collections.Counter(
        node["op"]
        for node in tool["match"]["nodes"]
        if node["op"] not in {"input", "parameter"}
    )


def run() -> None:
    verify()
    verify_tensor()
    library_raw = (RESULTS / "forged_tensor_tools.json").read_bytes()
    library = parse_library_bytes(library_raw)
    trace_raw = (RESULTS / "phase15_external_application_trace.json").read_bytes()
    trace = json.loads(trace_raw)
    rows = []
    reachable_pairs = 0
    for tool in library["tools"]:
        required = required_ops(tool)
        for workload in trace["rows"]:
            counts = target_counts(workload["export_graph"])
            coverage = {
                op: {
                    "required": count,
                    "available": available_count(counts, op),
                }
                for op, count in sorted(required.items())
            }
            unsupported_adapter_ops = sorted(op for op in required if op not in OP_TARGETS)
            reachable = not unsupported_adapter_ops and all(
                item["available"] >= item["required"] for item in coverage.values()
            )
            reachable_pairs += int(reachable)
            rows.append(
                {
                    "tool_id": tool["tool_id"],
                    "family": workload["family"],
                    "required_ops": dict(sorted(required.items())),
                    "coverage": coverage,
                    "unsupported_adapter_ops": unsupported_adapter_ops,
                    "coarse_reachable": reachable,
                    "exact_subgraph_match_executed": False,
                }
            )
    payload = {
        "version": "FOUNDRY_EXTERNAL_TOOL_REACHABILITY_V1",
        "status": (
            "EXTERNAL_TOOL_REACHABILITY_FOUND"
            if reachable_pairs
            else "EXTERNAL_TOOL_REACHABILITY_VALID_NEGATIVE"
        ),
        "library_file_sha256": sha(library_raw),
        "external_trace_sha256": sha(trace_raw),
        "tools": len(library["tools"]),
        "families": len(trace["rows"]),
        "pairs": len(rows),
        "coarse_reachable_pairs": reachable_pairs,
        "rows": rows,
        "P2": {
            "external_application_and_trace_component": (
                trace["status"] == "EXTERNAL_APPLICATION_TRACE_COMPONENT_READY"
            ),
            "forged_tool_domain_adapter": True,
            "at_least_one_reachable_pair": reachable_pairs > 0,
            "exact_subgraph_validation": False,
            "complete": False,
        },
        "interpretation": (
            "The frozen external applications are real and traceable, but none "
            "contains the minimum operation multiset required by any frozen "
            "forged tool. They cannot test tool reuse without changing the "
            "workload intake or forging tools from the external domain."
        ),
        "limits": [
            "operation-multiset coverage is only a necessary condition, never a sufficient subgraph match",
            "the adapter maps only frozen tool operations and observed ATen targets",
            "zero coarse reachability makes an exact matcher unnecessary for this intake",
            "the audit was performed after traces and is remediation evidence, not prospective evidence",
        ],
    }
    (RESULTS / "phase16_external_tool_reachability.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE16_EXTERNAL_REACHABILITY"
        f" status={payload['status']}"
        f" pairs={len(rows)}"
        f" reachable={reachable_pairs}"
        " p2_complete=false"
    )


if __name__ == "__main__":
    run()
