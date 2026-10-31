#!/usr/bin/env python3
"""Native/compiler deduplication for Pareto-selected typed tools."""

from __future__ import annotations

import hashlib
import json
import pathlib
import re
import time

import torch
from torch import nn
from torch._inductor.utils import run_and_get_code

from independent_pareto_tool_evaluator import (
    CapturingInterpreter,
    LIBRARY,
    execute_tool,
    max_error,
    parse_library,
    semantic_matches,
)
from phase65_independent_pareto_conformance import workloads


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
RESULT = RESULTS / "phase66_pareto_native_dedup.json"


def normalize_code(code: str) -> str:
    code = re.sub(
        r"/[^\n'\" ]+/(?:torchinductor|tmp)[^\n'\" ]*", "<PATH>", code
    )
    code = re.sub(r"\b[a-f0-9]{32,64}\b", "<HASH>", code)
    code = re.sub(r"\bc[0-9a-f]{8,}\b", "<CONST>", code)
    code = re.sub(r"(?m)^#.*$", "", code)
    return "\n".join(
        line.rstrip() for line in code.splitlines() if line.strip()
    )


def code_digest(codes: list[str]) -> str:
    normalized = "\n".join(normalize_code(code) for code in codes)
    return hashlib.sha256(normalized.encode()).hexdigest()


class ParetoToolModule(nn.Module):
    def __init__(self, tool: dict) -> None:
        super().__init__()
        self.tool = tool

    def forward(self, *inputs: object) -> object:
        return execute_tool(self.tool, list(inputs))


class StockCompositionModule(nn.Module):
    """Separate stock-ATen executor for the explicit candidate body."""

    def __init__(self, tool: dict) -> None:
        super().__init__()
        self.targets = [
            getattr(
                getattr(torch.ops.aten, node["target"].split(".")[1]),
                node["target"].split(".")[2],
            )
            for node in tool["nodes"]
        ]
        self.nodes = tool["nodes"]

    def term(
        self, term: dict, inputs: tuple[object, ...], values: list[object]
    ) -> object:
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
            return [self.term(value, inputs, values) for value in item]
        if tag == "tuple":
            return tuple(self.term(value, inputs, values) for value in item)
        if tag == "dict":
            return {
                self.term(key, inputs, values): self.term(
                    value, inputs, values
                )
                for key, value in item
            }
        raise RuntimeError("invalid frozen Pareto term")

    def forward(self, *inputs: object) -> object:
        values = []
        for target, node in zip(self.targets, self.nodes):
            args = self.term(node["args"], inputs, values)
            kwargs = self.term(node["kwargs"], inputs, values)
            values.append(target(*args, **kwargs))
        return values[-1]


def compile_receipt(module: nn.Module, inputs: tuple[object, ...]) -> dict:
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
    witnesses = []
    for suite, workload in workloads():
        try:
            exported = torch.export.export(
                workload["model"],
                workload["args"],
                workload["kwargs"],
                strict=True,
            )
            module = exported.module()
            interpreter = CapturingInterpreter(module)
            interpreter.run(*workload["args"], **workload["kwargs"])
            witnesses.append(
                (suite, workload["family"], module, interpreter)
            )
        except Exception:
            continue
    rows = []
    for tool in library["tools"]:
        example = None
        for suite, family, module, interpreter in witnesses:
            matches, _, _ = semantic_matches(tool, module.graph)
            if matches:
                path, bindings = matches[0]
                inputs = tuple(
                    interpreter.values[bindings[index]]
                    for index in range(len(tool["inputs"]))
                )
                example = (suite, family, path, inputs)
                break
        if example is None:
            raise RuntimeError(f"no native witness for {tool['tool_id']}")
        suite, family, path, inputs = example
        tool_module = ParetoToolModule(tool)
        stock_module = StockCompositionModule(tool)
        with torch.no_grad():
            tool_output = tool_module(*inputs)
            stock_output = stock_module(*inputs)
        error = max_error(tool_output, stock_output)
        if error > 1.0e-6:
            raise RuntimeError(
                f"Pareto stock decomposition mismatch {tool['tool_id']}"
            )
        tool_compile = compile_receipt(tool_module, inputs)
        stock_compile = compile_receipt(stock_module, inputs)
        compiled_both = (
            tool_compile["error"] is None
            and stock_compile["error"] is None
        )
        compiler_duplicate = (
            compiled_both
            and tool_compile["code_sha256"]
            == stock_compile["code_sha256"]
        )
        required_unsupported = (
            not compiled_both
            and tool_compile["error"] is not None
            and stock_compile["error"] is not None
        )
        rows.append(
            {
                "tool_id": tool["tool_id"],
                "calibration_suite": suite,
                "calibration_family": family,
                "calibration_nodes": [node.name for node in path],
                "stock_decomposition_exact": True,
                "decomposition_max_abs_error": error,
                "runtime_rewrite_exists": False,
                "tool_compile": {
                    key: value
                    for key, value in tool_compile.items()
                    if key != "output"
                },
                "stock_compile": {
                    key: value
                    for key, value in stock_compile.items()
                    if key != "output"
                },
                "normalized_inductor_duplicate": compiler_duplicate,
                "required_unsupported": required_unsupported,
                "native_decision": "REJECT_NATIVE_COMPOSITE_DUPLICATE",
                "semantic_search_candidate_retained": True,
            }
        )
    payload = {
        "version": "FOUNDRY_PARETO_NATIVE_DEDUP_V1",
        "status": "PARETO_NATIVE_DEDUP_COMPLETE",
        "library_sha256": hashlib.sha256(raw).hexdigest(),
        "rows": rows,
        "summary": {
            "tools": len(rows),
            "stock_decomposition_duplicates": len(rows),
            "compiled_both": sum(
                row["tool_compile"]["error"] is None
                and row["stock_compile"]["error"] is None
                for row in rows
            ),
            "normalized_inductor_duplicates": sum(
                row["normalized_inductor_duplicate"] for row in rows
            ),
            "required_unsupported": sum(
                row["required_unsupported"] for row in rows
            ),
            "runtime_inventions_admitted": 0,
            "semantic_search_candidates_retained": len(rows),
        },
        "limits": [
            "exact stock decomposition rejects runtime novelty",
            "compiler equality is sufficient duplicate evidence",
            "compiler inequality would not prove native novelty",
            "search-level portfolio utility remains independently testable",
        ],
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE66_PARETO_NATIVE_DEDUP_PASS"
        f" tools={len(rows)}"
        f" compiled={payload['summary']['compiled_both']}"
        f" duplicates={payload['summary']['normalized_inductor_duplicates']}"
        " native_admitted=0"
    )


if __name__ == "__main__":
    run()
