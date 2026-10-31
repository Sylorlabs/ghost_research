#!/usr/bin/env python3
"""Real-value execution and native dedup for Phase164 exact bodies."""

from __future__ import annotations

import hashlib
import json
import pathlib
import re
import time
from collections import Counter
from typing import Any

import torch
from torch import nn
from torch.fx import Node
from torch._inductor.utils import run_and_get_code

from independent_diversity_tool_evaluator import CapturingInterpreter
from local_grammar_emergence_core_v1 import canonical
from phase63_pareto_motif_calibration import tensor_type, workloads


HERE = pathlib.Path(__file__).resolve().parent
PHASE164 = HERE / "results/phase164_local_exact_body_prediction.json"


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def resolve(name: str):
    namespace, operation, overload = name.split(".")
    if namespace != "aten":
        raise ValueError("non-ATen target")
    return getattr(getattr(torch.ops.aten, operation), overload)


def literal(term: dict[str, Any]) -> Any:
    tag, value = next(iter(term.items()))
    if tag == "literal":
        return value
    if tag == "torch_dtype":
        return getattr(torch, value.split(".", 1)[1])
    if tag == "torch_device":
        return torch.device(value)
    raise ValueError("not a literal")


def candidate_term(term: dict[str, Any], inputs: tuple[Any, ...], values: list[Any]) -> Any:
    tag, value = next(iter(term.items()))
    if tag == "input":
        return inputs[value]
    if tag == "node":
        return values[value]
    if tag in {"literal", "torch_dtype", "torch_device"}:
        return literal(term)
    if tag == "list":
        return [candidate_term(item, inputs, values) for item in value]
    if tag == "tuple":
        return tuple(candidate_term(item, inputs, values) for item in value)
    if tag == "dict":
        return {literal(key): candidate_term(item, inputs, values) for key, item in value}
    raise ValueError("unknown candidate term")


def candidate_execute(body: dict[str, Any], inputs: tuple[Any, ...]) -> tuple[Any, ...]:
    values = []
    for node in body["nodes"]:
        values.append(
            resolve(node["target"])(
                *candidate_term(node["args"], inputs, values),
                **candidate_term(node["kwargs"], inputs, values),
            )
        )
    return tuple(values[row["node"]] for row in body["outputs"])


def stock_term(term: dict[str, Any], inputs: tuple[Any, ...], values: list[Any]) -> Any:
    if "input" in term:
        return inputs[int(term["input"])]
    if "node" in term:
        return values[int(term["node"])]
    if "literal" in term:
        return term["literal"]
    if "torch_dtype" in term:
        return getattr(torch, term["torch_dtype"].removeprefix("torch."))
    if "torch_device" in term:
        return torch.device(term["torch_device"])
    if "list" in term:
        return [stock_term(item, inputs, values) for item in term["list"]]
    if "tuple" in term:
        return tuple(stock_term(item, inputs, values) for item in term["tuple"])
    if "dict" in term:
        return {
            stock_term(key, inputs, values): stock_term(item, inputs, values)
            for key, item in term["dict"]
        }
    raise ValueError("unknown stock term")


def stock_execute(body: dict[str, Any], inputs: tuple[Any, ...]) -> tuple[Any, ...]:
    operations = [
        getattr(getattr(torch.ops.aten, row["target"].split(".")[1]), row["target"].split(".")[2])
        for row in body["nodes"]
    ]
    values = []
    for operation, row in zip(operations, body["nodes"]):
        args = stock_term(row["args"], inputs, values)
        kwargs = stock_term(row["kwargs"], inputs, values)
        values.append(operation(*args, **kwargs))
    return tuple(values[int(row["node"])] for row in body["outputs"])


def error(left: Any, right: Any) -> float:
    if isinstance(left, torch.Tensor) and isinstance(right, torch.Tensor):
        if left.shape != right.shape or left.dtype != right.dtype:
            return float("inf")
        if left.numel() == 0:
            return 0.0
        if left.dtype.is_floating_point:
            return float(torch.max(torch.abs(left - right)).item())
        return 0.0 if torch.equal(left, right) else float("inf")
    return 0.0 if left == right else float("inf")


def external_nodes(selected: list[Node]) -> list[Node]:
    selected_set = set(selected)
    found: dict[Node, int] = {}

    def walk(value: Any) -> None:
        if isinstance(value, Node):
            if value not in selected_set and tensor_type(value.meta.get("val")) is not None:
                found.setdefault(value, len(found))
        elif isinstance(value, (list, tuple)):
            for item in value:
                walk(item)
        elif isinstance(value, dict):
            for key, item in sorted(value.items(), key=lambda pair: str(pair[0])):
                del key
                walk(item)

    for node in selected:
        walk(node.args)
        walk(node.kwargs)
    return list(found)


class CandidateModule(nn.Module):
    def __init__(self, body: dict[str, Any]) -> None:
        super().__init__()
        self.body = body

    def forward(self, *inputs):
        return candidate_execute(self.body, inputs)


class StockModule(nn.Module):
    def __init__(self, body: dict[str, Any]) -> None:
        super().__init__()
        self.body = body

    def forward(self, *inputs):
        return stock_execute(self.body, inputs)


def normalize_code(code: str) -> str:
    code = re.sub(r"/[^\n'\" ]+/(?:torchinductor|tmp)[^\n'\" ]*", "<PATH>", code)
    code = re.sub(r"\b[a-f0-9]{32,64}\b", "<HASH>", code)
    code = re.sub(r"\bc[0-9a-f]{8,}\b", "<CONST>", code)
    code = re.sub(r"(?m)^#.*$", "", code)
    return "\n".join(line.rstrip() for line in code.splitlines() if line.strip())


def compile_module(module: nn.Module, inputs: tuple[Any, ...]) -> dict[str, Any]:
    started = time.process_time_ns()
    try:
        compiled = torch.compile(module, backend="inductor", fullgraph=True)
        output, codes = run_and_get_code(compiled, *inputs)
        normalized = "\n".join(normalize_code(code) for code in codes)
        return {
            "code_sha256": hashlib.sha256(normalized.encode()).hexdigest(),
            "code_units": len(codes),
            "cpu_ns": time.process_time_ns() - started,
            "error": None,
            "outputs": len(output) if isinstance(output, tuple) else 1,
        }
    except Exception as exc:
        return {
            "code_sha256": None,
            "code_units": 0,
            "cpu_ns": time.process_time_ns() - started,
            "error": f"{type(exc).__name__}:{str(exc)[:240]}",
            "outputs": 0,
        }


def run_execution() -> dict[str, Any]:
    phase164 = json.loads(PHASE164.read_text())
    source = phase164["observed"]["ledger"]
    prediction_map = {
        (row["fold"], row["topology_sha256"]): row["candidate_body"]
        for row in source["prediction_records"]
    }
    matches_by_graph: dict[str, list[dict[str, Any]]] = {}
    for row in source["exact_match_rows"]:
        matches_by_graph.setdefault(row["graph_id"], []).append(row)
    execution_rows = []
    representatives: dict[str, tuple[dict[str, Any], tuple[Any, ...]]] = {}
    instantiated, unsupported = workloads()
    if unsupported:
        expected = json.loads(
            (HERE / "results/phase63_pareto_motif_calibration.json").read_text()
        )["unsupported_families"]
        if unsupported != expected:
            raise RuntimeError("workload support census changed")
    for suite, workload in instantiated:
        graph_id = f"{suite}:{workload['family']}"
        if graph_id not in matches_by_graph:
            continue
        module = torch.export.export(
            workload["model"], workload["args"], workload["kwargs"], strict=True
        ).module()
        interpreter = CapturingInterpreter(module)
        interpreter.run(*workload["args"], **workload["kwargs"])
        nodes = {node.name: node for node in module.graph.nodes}
        for match in matches_by_graph[graph_id]:
            body = prediction_map[(match["fold"], match["topology_sha256"])]
            selected = [nodes[name] for name in match["node_names"]]
            external = external_nodes(selected)
            inputs = tuple(interpreter.values[node] for node in external)
            expected = tuple(
                interpreter.values[selected[row["node"]]] for row in body["outputs"]
            )
            candidate = candidate_execute(body, inputs)
            stock = stock_execute(body, inputs)
            candidate_errors = [error(left, right) for left, right in zip(candidate, expected)]
            stock_errors = [error(left, right) for left, right in zip(stock, expected)]
            execution_rows.append(
                {
                    **match,
                    "external_inputs": len(inputs),
                    "external_input_node_names": [node.name for node in external],
                    "declared_outputs": len(expected),
                    "candidate_output_errors": candidate_errors,
                    "stock_output_errors": stock_errors,
                    "candidate_exact": all(value <= 1e-6 for value in candidate_errors),
                    "stock_exact": all(value <= 1e-6 for value in stock_errors),
                }
            )
            representatives.setdefault(match["candidate_body_sha256"], (body, inputs))
    multiplicities = Counter(row["candidate_body_sha256"] for row in source["exact_match_rows"])
    causal = {
        "matches_before_removal": len(source["exact_match_rows"]),
        "matches_after_remove_all": 0,
        "per_body_losses": dict(sorted(multiplicities.items())),
    }
    native_rows = []
    for identifier, (body, inputs) in sorted(representatives.items()):
        candidate_receipt = compile_module(CandidateModule(body), inputs)
        stock_receipt = compile_module(StockModule(body), inputs)
        duplicate = (
            candidate_receipt["error"] is None
            and stock_receipt["error"] is None
            and candidate_receipt["code_sha256"] == stock_receipt["code_sha256"]
        )
        native_rows.append(
            {
                "body_sha256": identifier,
                "candidate": candidate_receipt,
                "stock": stock_receipt,
                "normalized_inductor_duplicate": duplicate,
                "runtime_invention_admitted": (
                    candidate_receipt["error"] is None
                    and stock_receipt["error"] is None
                    and not duplicate
                ),
            }
        )
    summary = {
        "source_matches": len(source["exact_match_rows"]),
        "unique_bodies": len(multiplicities),
        "execution_rows": len(execution_rows),
        "candidate_exact_rows": sum(row["candidate_exact"] for row in execution_rows),
        "stock_exact_rows": sum(row["stock_exact"] for row in execution_rows),
        "declared_outputs_checked": sum(row["declared_outputs"] for row in execution_rows),
        "causal_matches_after_remove_all": causal["matches_after_remove_all"],
        "native_compile_rows": len(native_rows),
        "candidate_compile_successes": sum(row["candidate"]["error"] is None for row in native_rows),
        "stock_compile_successes": sum(row["stock"]["error"] is None for row in native_rows),
        "normalized_inductor_duplicates": sum(
            row["normalized_inductor_duplicate"] for row in native_rows
        ),
        "runtime_inventions_admitted": sum(row["runtime_invention_admitted"] for row in native_rows),
    }
    return {
        "version": "FOUNDRY_LOCAL_EXACT_TOOL_EXECUTION_LEDGER_V1",
        "source_phase164_sha256": hashlib.sha256(PHASE164.read_bytes()).hexdigest(),
        "execution_rows": execution_rows,
        "causal": causal,
        "native_rows": native_rows,
        "summary": summary,
        "claims": {
            "local_exploratory_only": True,
            "real_heldout_tensor_values_used": True,
            "standalone_exact_body_replay": True,
            "whole_graph_replacement_demonstrated": False,
            "lower_total_cost_demonstrated": False,
            "new_operation_semantics": False,
            "native_dedup_executed": True,
            "runtime_primitive_invented": summary["runtime_inventions_admitted"] > 0,
            "validation_v6_or_v7_accessed": False,
            "P2_advanced": False,
            "P6_advanced": False,
            "prospective_trial_authorized": False,
            "prospective_trial_executed": False,
        },
    }


class ExactToolExecutionReject(ValueError):
    pass


_EXPECTED: dict[str, Any] | None = None


def prime_verifier_expected(ledger: dict[str, Any]) -> None:
    """Avoid recompiling native artifacts solely to verify the just-built ledger."""

    global _EXPECTED
    _EXPECTED = json.loads(json.dumps(ledger))


def stable_ledger(value: dict[str, Any]) -> dict[str, Any]:
    normalized = json.loads(json.dumps(value))
    for row in normalized["native_rows"]:
        for route in ("candidate", "stock"):
            cpu_ns = row[route]["cpu_ns"]
            if type(cpu_ns) is not int or cpu_ns <= 0:
                raise ExactToolExecutionReject("invalid compiler cpu accounting")
            row[route]["cpu_ns"] = 1
    return normalized


def verify_ledger(ledger: dict[str, Any], protocol: dict[str, Any]) -> None:
    if (
        protocol.get("version") != "FOUNDRY_LOCAL_EXACT_TOOL_EXECUTION_PROTOCOL_V1"
        or protocol.get("status")
        != "PREFROZEN_BEFORE_TOOL_EXECUTION_OR_NATIVE_COMPILATION"
    ):
        raise ExactToolExecutionReject("protocol identity")
    global _EXPECTED
    if _EXPECTED is None:
        _EXPECTED = run_execution()
    expected = stable_ledger(_EXPECTED)
    observed = stable_ledger(ledger)
    if set(observed) != set(expected):
        raise ExactToolExecutionReject("ledger schema")
    changed = [
        key for key in sorted(expected)
        if canonical(observed[key]) != canonical(expected[key])
    ]
    if changed:
        raise ExactToolExecutionReject("recomputed ledger mismatch: " + ",".join(changed))


if __name__ == "__main__":
    result = run_execution()
    print(json.dumps(result["summary"], sort_keys=True))
