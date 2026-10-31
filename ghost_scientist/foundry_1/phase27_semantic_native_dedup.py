#!/usr/bin/env python3
"""Native/compiler deduplication for machine-constructed semantic tools."""

from __future__ import annotations

import hashlib
import json
import pathlib
import re
import time

import torch
from torch import nn
from torch._inductor.utils import run_and_get_code

from external_validation_v2_2_runtime import constructors
from phase26_independent_semantic_evaluator import (
    CapturingInterpreter,
    execute_tool,
    max_error,
    parse_library,
    semantic_matches,
)


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
LIBRARY = RESULTS / "forged_semantic_tools.json"


def normalize_code(code: str) -> str:
    code = re.sub(r"/[^\n'\" ]+/(?:torchinductor|tmp)[^\n'\" ]*", "<PATH>", code)
    code = re.sub(r"\b[a-f0-9]{32,64}\b", "<HASH>", code)
    code = re.sub(r"\bc[0-9a-f]{8,}\b", "<CONST>", code)
    code = re.sub(r"(?m)^#.*$", "", code)
    return "\n".join(line.rstrip() for line in code.splitlines() if line.strip())


def code_digest(codes: list[str]) -> str:
    normalized = "\n".join(normalize_code(code) for code in codes)
    return hashlib.sha256(normalized.encode()).hexdigest()


class SemanticToolModule(nn.Module):
    def __init__(self, tool):
        super().__init__()
        self.tool = tool

    def forward(self, *inputs):
        return execute_tool(self.tool, list(inputs))


class StockCompositionModule(nn.Module):
    """Separate stock-ATen executor for the same explicit decomposition."""

    def __init__(self, tool):
        super().__init__()
        self.targets = [
            getattr(
                getattr(torch.ops.aten, node["target"].split(".")[1]),
                node["target"].split(".")[2],
            )
            for node in tool["nodes"]
        ]
        self.nodes = tool["nodes"]

    def _term(self, term, inputs, values):
        tag, item = next(iter(term.items()))
        if tag == "input":
            return inputs[item]
        if tag == "node":
            return values[item]
        if tag == "literal":
            return item
        if tag == "torch_dtype":
            return getattr(torch, item.split(".", 1)[1])
        if tag == "torch_device":
            return torch.device(item)
        if tag == "list":
            return [self._term(value, inputs, values) for value in item]
        if tag == "tuple":
            return tuple(self._term(value, inputs, values) for value in item)
        if tag == "dict":
            return {
                self._term(key, inputs, values): self._term(value, inputs, values)
                for key, value in item
            }
        raise RuntimeError("invalid frozen semantic term")

    def forward(self, *inputs):
        values = []
        for target, node in zip(self.targets, self.nodes):
            args = self._term(node["args"], inputs, values)
            kwargs = self._term(node["kwargs"], inputs, values)
            values.append(target(*args, **kwargs))
        return values[-1]


def compile_receipt(module: nn.Module, inputs: tuple[object, ...]):
    started = time.process_time_ns()
    try:
        compiled = torch.compile(module, backend="inductor", fullgraph=True)
        output, codes = run_and_get_code(compiled, *inputs)
        return {
            "code_sha256": code_digest(codes),
            "code_units": len(codes),
            "error": None,
            "cpu_ns": time.process_time_ns() - started,
            "output": output,
        }
    except Exception as exc:
        return {
            "code_sha256": None,
            "code_units": 0,
            "error": f"{type(exc).__name__}:{str(exc)[:240]}",
            "cpu_ns": time.process_time_ns() - started,
            "output": None,
        }


def run() -> None:
    raw = LIBRARY.read_bytes()
    library = parse_library(raw)
    calibration = []
    for family, construct in constructors():
        try:
            workload = construct()
            exported = torch.export.export(
                workload["model"], workload["args"], workload["kwargs"], strict=True
            )
            module = exported.module()
            interpreter = CapturingInterpreter(module)
            interpreter.run(*workload["args"], **workload["kwargs"])
            calibration.append((family, module, interpreter))
        except Exception:
            continue
    rows = []
    for tool in library["tools"]:
        example = None
        for family, module, interpreter in calibration:
            matches, _, _ = semantic_matches(tool, module.graph)
            if matches:
                path, bindings = matches[0]
                inputs = tuple(
                    interpreter.values[bindings[index]]
                    for index in range(len(tool["inputs"]))
                )
                example = (family, path, inputs)
                break
        if example is None:
            raise RuntimeError(f"no calibration witness for {tool['tool_id']}")
        family, path, inputs = example
        semantic_module = SemanticToolModule(tool)
        stock_module = StockCompositionModule(tool)
        with torch.no_grad():
            semantic_output = semantic_module(*inputs)
            stock_output = stock_module(*inputs)
        decomposition_error = max_error(semantic_output, stock_output)
        if not decomposition_error <= 1.0e-6:
            raise RuntimeError(f"stock decomposition mismatch {tool['tool_id']}")
        semantic_receipt = compile_receipt(semantic_module, inputs)
        stock_receipt = compile_receipt(stock_module, inputs)
        compiled_both = (
            semantic_receipt["error"] is None and stock_receipt["error"] is None
        )
        compiler_duplicate = (
            compiled_both
            and semantic_receipt["code_sha256"]
            == stock_receipt["code_sha256"]
        )
        required_unsupported = (
            not compiled_both
            and semantic_receipt["error"] is not None
            and stock_receipt["error"] is not None
        )
        rows.append(
            {
                "tool_id": tool["tool_id"],
                "calibration_family": family,
                "calibration_nodes": [node.name for node in path],
                "stock_decomposition_exact": True,
                "decomposition_max_abs_error": decomposition_error,
                "runtime_rewrite_exists": False,
                "semantic_compile": {
                    key: value
                    for key, value in semantic_receipt.items()
                    if key != "output"
                },
                "stock_compile": {
                    key: value
                    for key, value in stock_receipt.items()
                    if key != "output"
                },
                "normalized_inductor_duplicate": compiler_duplicate,
                "required_unsupported": required_unsupported,
                "decision": "REJECT_NATIVE_COMPOSITE_DUPLICATE",
                "reason": (
                    "the generated tool is exactly decomposed into existing "
                    "stock ATen operations and supplies no distinct runtime lowering"
                ),
            }
        )
    if any(not row["stock_decomposition_exact"] for row in rows):
        raise RuntimeError("semantic native audit left an unclassified tool")
    payload = {
        "version": "FOUNDRY_SEMANTIC_NATIVE_DEDUP_V1",
        "status": "SEMANTIC_NATIVE_DEDUP_COMPLETE",
        "library_sha256": hashlib.sha256(raw).hexdigest(),
        "rows": rows,
        "summary": {
            "tools": len(rows),
            "stock_decomposition_duplicates": len(rows),
            "compiled_both": sum(
                row["semantic_compile"]["error"] is None
                and row["stock_compile"]["error"] is None
                for row in rows
            ),
            "normalized_inductor_duplicates": sum(
                row["normalized_inductor_duplicate"] for row in rows
            ),
            "required_unsupported": sum(row["required_unsupported"] for row in rows),
            "rejected": len(rows),
            "admitted": 0,
        },
        "P5": {
            "current_candidate_audit_executed": True,
            "all_candidates_classified": True,
            "runtime_inventions_admitted": 0,
            "complete": False
        },
        "limits": [
            "exact stock decomposition is sufficient to reject runtime novelty",
            "compiler code equality is a sufficient duplicate witness",
            "compiler code inequality would not prove novelty",
            "semantic search reuse remains separately testable",
        ],
    }
    (RESULTS / "phase27_semantic_native_dedup.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE27_SEMANTIC_NATIVE_PASS"
        f" tools={len(rows)}"
        f" compiled={payload['summary']['compiled_both']}"
        f" inductor_duplicates={payload['summary']['normalized_inductor_duplicates']}"
        f" unsupported={payload['summary']['required_unsupported']}"
        " rejected_runtime=all admitted=0"
    )


if __name__ == "__main__":
    run()
