#!/usr/bin/env python3
"""Independent real-value replay for Phase164 exact local tool matches.

This module deliberately stops before compilation or native deduplication.  It
authenticates the historical graph, maps the frozen motif's external inputs to
captured FX-node values, executes the exact body as an explicit composition of
stock ATen operations, and checks every declared output.
"""

from __future__ import annotations

from collections.abc import Mapping
import functools
import hashlib
import inspect
import json
import math
import os
import pathlib
import re
import time
from typing import Any

import torch
from torch import nn
from torch.fx import GraphModule, Interpreter, Node
from torch._inductor.utils import run_and_get_code

from local_grammar_emergence_core_v1 import (
    canonical,
    construct_body,
    digest,
    eligible_nodes,
    enumerate_motifs,
)
from phase63_pareto_motif_calibration import (
    old_repository,
    tensor_type,
    workloads,
)


HERE = pathlib.Path(__file__).resolve().parent
FREEZE = HERE / "results/local_exact_tool_execution_v1_freeze.json"
PROTOCOL = (
    HERE / "arm_adapter_fixtures/LOCAL_EXACT_TOOL_EXECUTION_PROTOCOL_V1.json"
)
PHASE164 = HERE / "results/phase164_local_exact_body_prediction.json"
POOL = HERE / "results/pareto_tool_pool.json"
TOLERANCE = 1.0e-6
INSTANTIATION_SEED = int.from_bytes(
    hashlib.sha256(b"foundry-phase165-independent-runtime-v1").digest()[:8],
    "big",
) % (2**31)

# The three frozen exact bodies contain only these operations.  An explicit
# table makes this a stock-composition control, not a second generic target
# resolver sharing the candidate interpreter's implementation.
EXPLICIT_STOCK_ATEN = {
    "aten.linear.default": torch.ops.aten.linear.default,
    "aten.relu.default": torch.ops.aten.relu.default,
}


class IndependentLocalExactExecutionReject(ValueError):
    """The proposed replay or ledger violates the frozen execution contract."""


# Public name expected by the Phase165 dual-verifier harness.
IndependentExactToolExecutionReject = IndependentLocalExactExecutionReject


def _sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _canonical_json(value: object) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n"
    ).encode()


def _tree_clone(value: Any, memo: dict[int, Any] | None = None) -> Any:
    """Clone tensor trees while preserving repeated-object alias identity."""

    if memo is None:
        memo = {}
    identity = id(value)
    if isinstance(value, torch.Tensor):
        if identity not in memo:
            memo[identity] = (
                value.detach()
                .clone()
                .requires_grad_(value.requires_grad)
            )
        return memo[identity]
    if isinstance(value, tuple):
        return tuple(_tree_clone(item, memo) for item in value)
    if isinstance(value, list):
        return [_tree_clone(item, memo) for item in value]
    if isinstance(value, Mapping):
        return {
            key: _tree_clone(item, memo) for key, item in value.items()
        }
    return value


class _Capture(Interpreter):
    def __init__(self, module: GraphModule):
        super().__init__(module)
        self.values: dict[str, Any] = {}

    def run_node(self, node: Node) -> Any:
        value = super().run_node(node)
        if node.name in self.values:
            raise IndependentLocalExactExecutionReject(
                f"duplicate FX node name during capture: {node.name}"
            )
        self.values[node.name] = value
        return value


def _capture(
    module: GraphModule,
    args: tuple[Any, ...],
    kwargs: dict[str, Any],
) -> dict[str, Any]:
    signature = inspect.signature(module.forward)
    try:
        bound = signature.bind(
            *_tree_clone(args), **_tree_clone(kwargs)
        )
    except TypeError as error:
        raise IndependentLocalExactExecutionReject(
            "authenticated workload does not bind to exported GraphModule"
        ) from error
    bound.apply_defaults()
    runner = _Capture(module)
    with torch.no_grad():
        runner.run(*bound.arguments.values())
    expected_names = [node.name for node in module.graph.nodes]
    if len(expected_names) != len(set(expected_names)):
        raise IndependentLocalExactExecutionReject(
            "FX graph contains duplicate node names"
        )
    if set(runner.values) != set(expected_names):
        raise IndependentLocalExactExecutionReject(
            "capture did not visit every authenticated FX node exactly once"
        )
    return runner.values


def _literal(term: dict[str, Any]) -> Any:
    if set(term) != {next(iter(term), None)} or len(term) != 1:
        raise IndependentLocalExactExecutionReject(
            "encoded literal must have exactly one tag"
        )
    tag, value = next(iter(term.items()))
    if tag == "literal":
        if value is not None and type(value) not in {
            bool,
            int,
            float,
            str,
        }:
            raise IndependentLocalExactExecutionReject(
                "unsupported encoded literal"
            )
        return value
    if tag == "torch_dtype":
        if not isinstance(value, str) or not value.startswith("torch."):
            raise IndependentLocalExactExecutionReject(
                "invalid encoded torch dtype"
            )
        result = getattr(torch, value.removeprefix("torch."), None)
        if not isinstance(result, torch.dtype):
            raise IndependentLocalExactExecutionReject(
                "unknown encoded torch dtype"
            )
        return result
    if tag == "torch_device":
        try:
            return torch.device(value)
        except (TypeError, RuntimeError) as error:
            raise IndependentLocalExactExecutionReject(
                "invalid encoded torch device"
            ) from error
    raise IndependentLocalExactExecutionReject(
        f"unsupported literal tag: {tag}"
    )


def _check_type(value: Any, expected: dict[str, Any], label: str) -> None:
    observed = tensor_type(value)
    if observed != expected:
        raise IndependentLocalExactExecutionReject(
            f"{label} type mismatch: {observed!r} != {expected!r}"
        )


def _bind_term(
    encoded: dict[str, Any],
    actual: Any,
    selected: list[Node],
    bindings: dict[int, Node],
) -> None:
    """Bind encoded input indices to the exact external FX nodes.

    The walk follows the frozen body's encoded terms rather than guessing from
    ``all_input_nodes``.  That distinction preserves first-use input order and
    handles repeated external nodes correctly.
    """

    if not isinstance(encoded, dict) or len(encoded) != 1:
        raise IndependentLocalExactExecutionReject(
            "malformed encoded source term"
        )
    tag, value = next(iter(encoded.items()))
    if tag == "input":
        index = int(value)
        if not isinstance(actual, Node) or actual in selected:
            raise IndependentLocalExactExecutionReject(
                "encoded external input is not an external FX node"
            )
        prior = bindings.setdefault(index, actual)
        if prior is not actual:
            raise IndependentLocalExactExecutionReject(
                f"external input {index} maps to multiple FX nodes"
            )
        return
    if tag == "node":
        index = int(value)
        if index >= len(selected) or actual is not selected[index]:
            raise IndependentLocalExactExecutionReject(
                "encoded internal node reference mismatch"
            )
        return
    if tag in {"literal", "torch_dtype", "torch_device"}:
        expected = _literal(encoded)
        if type(actual) is not type(expected) or actual != expected:
            raise IndependentLocalExactExecutionReject(
                f"encoded literal mismatch: {actual!r} != {expected!r}"
            )
        return
    if tag in {"list", "tuple"}:
        sequence_type = list if tag == "list" else tuple
        if not isinstance(actual, sequence_type) or len(actual) != len(value):
            raise IndependentLocalExactExecutionReject(
                f"encoded {tag} source mismatch"
            )
        for child, source in zip(value, actual, strict=True):
            _bind_term(child, source, selected, bindings)
        return
    if tag == "dict":
        if not isinstance(actual, Mapping) or len(actual) != len(value):
            raise IndependentLocalExactExecutionReject(
                "encoded dict source mismatch"
            )
        ordered_actual = sorted(actual.items(), key=lambda pair: str(pair[0]))
        for pair, (actual_key, actual_value) in zip(
            value, ordered_actual, strict=True
        ):
            if not isinstance(pair, list) or len(pair) != 2:
                raise IndependentLocalExactExecutionReject(
                    "malformed encoded dict pair"
                )
            expected_key = _literal(pair[0])
            if (
                type(actual_key) is not type(expected_key)
                or actual_key != expected_key
            ):
                raise IndependentLocalExactExecutionReject(
                    "encoded dict key mismatch"
                )
            _bind_term(pair[1], actual_value, selected, bindings)
        return
    raise IndependentLocalExactExecutionReject(
        f"unsupported encoded source term: {tag}"
    )


def bind_external_nodes(
    body: dict[str, Any],
    selected: list[Node],
) -> list[Node]:
    if len(body["nodes"]) != len(selected):
        raise IndependentLocalExactExecutionReject(
            "selected-node count differs from exact body"
        )
    bindings: dict[int, Node] = {}
    for encoded_node, source_node in zip(
        body["nodes"], selected, strict=True
    ):
        if str(source_node.target) != encoded_node["target"]:
            raise IndependentLocalExactExecutionReject(
                "selected-node target differs from exact body"
            )
        _check_type(
            source_node.meta.get("val"),
            encoded_node["output_type"],
            f"source node {source_node.name}",
        )
        _bind_term(
            encoded_node["args"],
            source_node.args,
            selected,
            bindings,
        )
        _bind_term(
            encoded_node["kwargs"],
            source_node.kwargs,
            selected,
            bindings,
        )
    expected_indices = set(range(len(body["inputs"])))
    if set(bindings) != expected_indices:
        raise IndependentLocalExactExecutionReject(
            "external input indices are not complete and contiguous"
        )
    external = [bindings[index] for index in range(len(body["inputs"]))]
    for index, (node, input_row) in enumerate(
        zip(external, body["inputs"], strict=True)
    ):
        _check_type(
            node.meta.get("val"),
            input_row["type"],
            f"external input {index}",
        )
    return external


def _execute_term(
    term: dict[str, Any],
    inputs: list[Any],
    nodes: list[Any],
) -> Any:
    if not isinstance(term, dict) or len(term) != 1:
        raise IndependentLocalExactExecutionReject(
            "malformed execution term"
        )
    tag, value = next(iter(term.items()))
    if tag == "input":
        try:
            return inputs[int(value)]
        except (IndexError, ValueError) as error:
            raise IndependentLocalExactExecutionReject(
                "execution input reference out of range"
            ) from error
    if tag == "node":
        try:
            return nodes[int(value)]
        except (IndexError, ValueError) as error:
            raise IndependentLocalExactExecutionReject(
                "execution node reference out of range"
            ) from error
    if tag in {"literal", "torch_dtype", "torch_device"}:
        return _literal(term)
    if tag == "list":
        return [_execute_term(item, inputs, nodes) for item in value]
    if tag == "tuple":
        return tuple(_execute_term(item, inputs, nodes) for item in value)
    if tag == "dict":
        return {
            _literal(pair[0]): _execute_term(pair[1], inputs, nodes)
            for pair in value
        }
    raise IndependentLocalExactExecutionReject(
        f"unsupported execution term: {tag}"
    )


def execute_explicit_stock_body(
    body: dict[str, Any],
    inputs: list[Any],
) -> tuple[Any, ...]:
    if len(inputs) != len(body["inputs"]):
        raise IndependentLocalExactExecutionReject(
            "runtime input arity differs from body declaration"
        )
    cloned_inputs = _tree_clone(inputs)
    for index, (value, declaration) in enumerate(
        zip(cloned_inputs, body["inputs"], strict=True)
    ):
        _check_type(value, declaration["type"], f"runtime input {index}")
    values: list[Any] = []
    with torch.no_grad():
        for index, node in enumerate(body["nodes"]):
            target = EXPLICIT_STOCK_ATEN.get(node["target"])
            if target is None:
                raise IndependentLocalExactExecutionReject(
                    f"target absent from explicit stock table: "
                    f"{node['target']}"
                )
            args = _execute_term(node["args"], cloned_inputs, values)
            kwargs = _execute_term(node["kwargs"], cloned_inputs, values)
            if not isinstance(args, tuple) or not isinstance(kwargs, dict):
                raise IndependentLocalExactExecutionReject(
                    "body node args/kwargs do not decode to tuple/dict"
                )
            value = target(*args, **kwargs)
            _check_type(
                value, node["output_type"], f"executed node {index}"
            )
            values.append(value)
    outputs: list[Any] = []
    for output in body["outputs"]:
        if not isinstance(output, dict) or set(output) != {"node"}:
            raise IndependentLocalExactExecutionReject(
                "declared output is not a node reference"
            )
        index = int(output["node"])
        if index < 0 or index >= len(values):
            raise IndependentLocalExactExecutionReject(
                "declared output reference out of range"
            )
        outputs.append(values[index])
    if not outputs:
        raise IndependentLocalExactExecutionReject(
            "exact body declares no outputs"
        )
    # Always return a tuple.  Collapsing a single output would make a future
    # multi-output body ambiguous and could allow an omitted output to pass.
    return tuple(outputs)


def _tensor_leaves(value: Any) -> list[torch.Tensor]:
    if isinstance(value, torch.Tensor):
        return [value]
    if isinstance(value, (tuple, list)):
        return [
            tensor
            for item in value
            for tensor in _tensor_leaves(item)
        ]
    if isinstance(value, Mapping):
        return [
            tensor
            for key in sorted(value, key=str)
            for tensor in _tensor_leaves(value[key])
        ]
    return []


def _metadata(value: Any) -> Any:
    if isinstance(value, torch.Tensor):
        return {
            "tensor": {
                "shape": list(value.shape),
                "dtype": str(value.dtype),
                "layout": str(value.layout),
                "stride": (
                    list(value.stride())
                    if value.layout == torch.strided
                    else None
                ),
            }
        }
    if isinstance(value, tuple):
        return {"tuple": [_metadata(item) for item in value]}
    if isinstance(value, list):
        return {"list": [_metadata(item) for item in value]}
    if isinstance(value, Mapping):
        return {
            "dict": [
                [str(key), _metadata(value[key])]
                for key in sorted(value, key=str)
            ]
        }
    if value is None or type(value) in {bool, int, float, str}:
        return {"literal": value}
    raise IndependentLocalExactExecutionReject(
        f"unsupported runtime value: {type(value).__name__}"
    )


def _alias_matrix(value: Any) -> list[list[bool]]:
    leaves = _tensor_leaves(value)
    return [
        [
            (
                left is right
                if left.layout != torch.strided
                or right.layout != torch.strided
                else left.untyped_storage().data_ptr()
                == right.untyped_storage().data_ptr()
            )
            for right in leaves
        ]
        for left in leaves
    ]


def _value_digest(value: Any) -> str:
    result = hashlib.sha256(
        json.dumps(
            _metadata(value), sort_keys=True, separators=(",", ":")
        ).encode()
    )
    for tensor in _tensor_leaves(value):
        dense = tensor.detach().cpu()
        if dense.layout != torch.strided:
            dense = dense.to_dense()
        result.update(
            dense.contiguous()
            .reshape(-1)
            .view(torch.uint8)
            .numpy()
            .tobytes()
        )
    return result.hexdigest()


def compare_all_declared_outputs(
    expected: tuple[Any, ...],
    actual: tuple[Any, ...],
) -> dict[str, Any]:
    if len(expected) != len(actual):
        raise IndependentLocalExactExecutionReject(
            "declared output count mismatch"
        )
    if _metadata(expected) != _metadata(actual):
        raise IndependentLocalExactExecutionReject(
            "declared output structure or metadata mismatch"
        )
    maximum = 0.0
    exact_nonfloating = True
    for left, right in zip(
        _tensor_leaves(expected), _tensor_leaves(actual), strict=True
    ):
        if left.dtype.is_floating_point or left.dtype.is_complex:
            if left.numel():
                error = float(
                    (left.detach() - right.detach()).abs().max().item()
                )
                if not math.isfinite(error):
                    raise IndependentLocalExactExecutionReject(
                        "nonfinite floating output error"
                    )
                maximum = max(maximum, error)
            try:
                torch.testing.assert_close(
                    right,
                    left,
                    rtol=TOLERANCE,
                    atol=TOLERANCE,
                    equal_nan=False,
                    check_device=True,
                    check_dtype=True,
                    check_layout=True,
                    check_stride=True,
                )
            except Exception as error:
                raise IndependentLocalExactExecutionReject(
                    "floating declared output mismatch"
                ) from error
        elif not torch.equal(left.detach(), right.detach()):
            exact_nonfloating = False
            raise IndependentLocalExactExecutionReject(
                "nonfloating declared output mismatch"
            )
    aliases_equal = _alias_matrix(expected) == _alias_matrix(actual)
    if not aliases_equal:
        raise IndependentLocalExactExecutionReject(
            "declared output alias relation mismatch"
        )
    return {
        "declared_outputs": len(expected),
        "max_abs_error": maximum,
        "nonfloating_exact": exact_nonfloating,
        "alias_relation_equal": aliases_equal,
        "expected_sha256": _value_digest(expected),
        "actual_sha256": _value_digest(actual),
    }


def _authenticated_protocol() -> dict[str, Any]:
    freeze = json.loads(FREEZE.read_text(encoding="utf-8"))
    protocol = json.loads(PROTOCOL.read_text(encoding="utf-8"))
    if (
        freeze["status"]
        != "FROZEN_BEFORE_TOOL_EXECUTION_CAUSALITY_OR_NATIVE_COMPILATION"
        or freeze["protocol_sha256"] != _sha(PROTOCOL)
        or protocol["execution"]["matches"] != 17
        or protocol["execution"]["unique_predicted_bodies"] != 3
        or protocol["execution"]["floating_tolerance"] != TOLERANCE
        or protocol["decision_rule"][
            "never_call_standalone_replay_whole_graph_replacement"
        ]
        is not True
        or protocol["decision_rule"][
            "never_advance_P2_or_P6_or_authorize_prospective_trial"
        ]
        is not True
    ):
        raise IndependentLocalExactExecutionReject(
            "frozen execution protocol boundary"
        )
    for provider in freeze["provider_records"]:
        if _sha(HERE / provider["path"]) != provider["sha256"]:
            raise IndependentLocalExactExecutionReject(
                f"frozen provider mismatch: {provider['path']}"
            )
    return protocol


def _runtime_graphs() -> dict[str, dict[str, Any]]:
    pool = json.loads(POOL.read_text(encoding="utf-8"))
    expected = {
        row["graph_id"]: row for row in pool["calibration_graphs"]
    }
    torch.manual_seed(INSTANTIATION_SEED)
    instantiated, unsupported = workloads()
    phase63 = json.loads(
        (
            HERE / "results/phase63_pareto_motif_calibration.json"
        ).read_text(encoding="utf-8")
    )
    if unsupported != phase63["unsupported_families"]:
        raise IndependentLocalExactExecutionReject(
            "historical unsupported-workload census changed"
        )
    rows: dict[str, dict[str, Any]] = {}
    for suite, workload in instantiated:
        graph_id = f"{suite}:{workload['family']}"
        if graph_id not in expected or graph_id in rows:
            raise IndependentLocalExactExecutionReject(
                f"runtime graph identity mismatch: {graph_id}"
            )
        exported = torch.export.export(
            workload["model"],
            workload["args"],
            workload["kwargs"],
            strict=True,
        )
        module = exported.module()
        graph_sha256 = hashlib.sha256(
            str(module.graph).encode()
        ).hexdigest()
        if graph_sha256 != expected[graph_id]["graph_sha256"]:
            raise IndependentLocalExactExecutionReject(
                f"authenticated graph digest changed: {graph_id}"
            )
        rows[graph_id] = {
            "graph_id": graph_id,
            "suite": suite,
            "family": workload["family"],
            "repository": workload.get(
                "repository",
                old_repository(suite, workload["family"]),
            ),
            "graph_sha256": graph_sha256,
            "graph": module.graph,
            "module": module,
            "args": workload["args"],
            "kwargs": workload["kwargs"],
        }
    if len(rows) != 23 or set(rows) != set(expected):
        raise IndependentLocalExactExecutionReject(
            "authenticated runtime graph census changed"
        )
    return rows


def _source_motif(
    graph_row: dict[str, Any],
    exact_row: dict[str, Any],
) -> tuple[dict[str, Any], list[Node]]:
    record = enumerate_motifs(graph_row)
    matches = [
        motif
        for motif in record["motifs"]
        if (
            motif["node_names"] == exact_row["node_names"]
            and motif["topology_sha256"]
            == exact_row["topology_sha256"]
            and motif["body_sha256"] == exact_row["body_sha256"]
        )
    ]
    if len(matches) != 1:
        raise IndependentLocalExactExecutionReject(
            "exact row does not resolve to one authenticated source motif"
        )
    motif = matches[0]
    by_name = {node.name: node for node in graph_row["graph"].nodes}
    try:
        selected = [by_name[name] for name in motif["node_names"]]
    except KeyError as error:
        raise IndependentLocalExactExecutionReject(
            "frozen motif node name absent from authenticated graph"
        ) from error
    if canonical(construct_body(selected, tuple(range(len(selected))))) != canonical(
        motif["body"]
    ):
        raise IndependentLocalExactExecutionReject(
            "node-name mapping does not reconstruct frozen motif body"
        )
    return motif, selected


@functools.lru_cache(maxsize=1)
def expected_execution_ledger() -> dict[str, Any]:
    """Recompute the complete independent 17-match real-value ledger."""

    _authenticated_protocol()
    phase164 = json.loads(PHASE164.read_text(encoding="utf-8"))
    prediction = phase164["observed"]["ledger"]
    exact_rows = prediction["exact_match_rows"]
    prediction_by_key = {
        (row["fold"], row["topology_sha256"]): row
        for row in prediction["prediction_records"]
    }
    runtime_graphs = _runtime_graphs()
    receipts: list[dict[str, Any]] = []
    body_hashes: set[str] = set()
    for exact_row in exact_rows:
        graph_row = runtime_graphs[exact_row["graph_id"]]
        predicted = prediction_by_key.get(
            (exact_row["fold"], exact_row["topology_sha256"])
        )
        if predicted is None:
            raise IndependentLocalExactExecutionReject(
                "exact row has no frozen prediction"
            )
        body = predicted["candidate_body"]
        if (
            digest(body) != exact_row["candidate_body_sha256"]
            or exact_row["candidate_body_sha256"]
            != exact_row["body_sha256"]
        ):
            raise IndependentLocalExactExecutionReject(
                "exact row candidate/source body digest mismatch"
            )
        motif, selected = _source_motif(graph_row, exact_row)
        if canonical(body) != canonical(motif["body"]):
            raise IndependentLocalExactExecutionReject(
                "predicted body bytes differ from source motif"
            )
        external_nodes = bind_external_nodes(body, selected)
        seed = int.from_bytes(
            hashlib.sha256(
                (
                    "foundry-phase165-real-values-v1:"
                    + exact_row["graph_id"]
                    + ":"
                    + ",".join(exact_row["node_names"])
                ).encode()
            ).digest()[:8],
            "big",
        ) % (2**31)
        torch.manual_seed(seed)
        captures = _capture(
            graph_row["module"],
            graph_row["args"],
            graph_row["kwargs"],
        )
        inputs = [captures[node.name] for node in external_nodes]
        expected = tuple(
            captures[selected[int(output["node"])].name]
            for output in body["outputs"]
        )
        actual = execute_explicit_stock_body(body, inputs)
        comparison = compare_all_declared_outputs(expected, actual)
        body_hashes.add(exact_row["candidate_body_sha256"])
        receipts.append(
            {
                "graph_id": exact_row["graph_id"],
                "family": exact_row["family"],
                "fold": exact_row["fold"],
                "topology_sha256": exact_row["topology_sha256"],
                "body_sha256": exact_row["body_sha256"],
                "node_names": exact_row["node_names"],
                "external_node_names": [
                    node.name for node in external_nodes
                ],
                "seed": seed,
                "targets": [
                    node["target"] for node in body["nodes"]
                ],
                **comparison,
            }
        )

    if (
        len(receipts) != 17
        or len(body_hashes) != 3
        or any(
            receipt["max_abs_error"] > TOLERANCE
            for receipt in receipts
        )
    ):
        raise IndependentLocalExactExecutionReject(
            "independent execution census or numerical gate"
        )
    return {
        "version": "FOUNDRY_INDEPENDENT_LOCAL_EXACT_EXECUTION_LEDGER_V1",
        "status": "INDEPENDENT_STOCK_ATEN_EXECUTION_PASS",
        "instantiation_seed": INSTANTIATION_SEED,
        "receipts": receipts,
        "summary": {
            "authenticated_graphs": len(runtime_graphs),
            "exact_matches_executed": len(receipts),
            "unique_bodies_executed": len(body_hashes),
            "declared_outputs_checked": sum(
                receipt["declared_outputs"] for receipt in receipts
            ),
            "maximum_abs_error": max(
                receipt["max_abs_error"] for receipt in receipts
            ),
        },
        "claims": {
            "bounded_local_real_value_replay_only": True,
            "whole_graph_replacement_claimed": False,
            "native_compilation_executed": False,
            "native_dedup_executed": False,
            "runtime_primitive_invented": False,
            "P2_advanced": False,
            "P6_advanced": False,
            "prospective_trial_authorized": False,
            "prospective_trial_executed": False,
        },
    }


def verify_execution_ledger(proposed: dict[str, Any]) -> None:
    """Strictly reject any byte-level departure from independent replay."""

    expected = expected_execution_ledger()
    if set(proposed) != set(expected):
        raise IndependentLocalExactExecutionReject(
            "independent execution ledger schema mismatch"
        )
    changed = [
        key
        for key in sorted(expected)
        if _canonical_json(proposed[key])
        != _canonical_json(expected[key])
    ]
    if changed:
        raise IndependentLocalExactExecutionReject(
            "independent execution ledger mismatch: " + ",".join(changed)
        )


def verify_ledger(proposed: dict[str, Any], protocol: dict[str, Any]) -> None:
    """Verify the primary Phase165 schema against independent real-value replay."""

    if (
        protocol.get("version")
        != "FOUNDRY_LOCAL_EXACT_TOOL_EXECUTION_PROTOCOL_V1"
        or protocol.get("status")
        != "PREFROZEN_BEFORE_TOOL_EXECUTION_OR_NATIVE_COMPILATION"
    ):
        raise IndependentLocalExactExecutionReject("protocol identity")
    independent = expected_execution_ledger()
    expected = {
        (
            row["graph_id"],
            row["fold"],
            row["topology_sha256"],
            row["body_sha256"],
            tuple(row["node_names"]),
        ): row
        for row in independent["receipts"]
    }
    if (
        proposed.get("version")
        != "FOUNDRY_LOCAL_EXACT_TOOL_EXECUTION_LEDGER_V1"
        or proposed.get("source_phase164_sha256") != _sha(PHASE164)
        or len(proposed.get("execution_rows", [])) != len(expected) != 0
    ):
        raise IndependentLocalExactExecutionReject("primary execution identity")
    observed_bodies = []
    for row in proposed["execution_rows"]:
        key = (
            row["graph_id"],
            row["fold"],
            row["topology_sha256"],
            row["body_sha256"],
            tuple(row["node_names"]),
        )
        witness = expected.get(key)
        if (
            witness is None
            or row["external_input_node_names"]
            != witness["external_node_names"]
            or row["external_inputs"] != len(witness["external_node_names"])
            or row["declared_outputs"] != witness["declared_outputs"]
            or len(row["candidate_output_errors"]) != witness["declared_outputs"]
            or len(row["stock_output_errors"]) != witness["declared_outputs"]
            or not all(type(value) in (int, float) and 0 <= value <= TOLERANCE for value in row["candidate_output_errors"])
            or not all(type(value) in (int, float) and 0 <= value <= TOLERANCE for value in row["stock_output_errors"])
            or row["candidate_exact"] is not True
            or row["stock_exact"] is not True
            or witness["max_abs_error"] > TOLERANCE
        ):
            raise IndependentLocalExactExecutionReject("primary execution row")
        observed_bodies.append(row["candidate_body_sha256"])
    multiplicities = {
        key: observed_bodies.count(key) for key in sorted(set(observed_bodies))
    }
    causal = proposed.get("causal", {})
    if causal != {
        "matches_before_removal": 17,
        "matches_after_remove_all": 0,
        "per_body_losses": multiplicities,
    }:
        raise IndependentLocalExactExecutionReject("causal relation")
    native = proposed.get("native_rows", [])
    if len(native) != 3 or {row["body_sha256"] for row in native} != set(multiplicities):
        raise IndependentLocalExactExecutionReject("native census")
    for row in native:
        candidate = row["candidate"]
        stock = row["stock"]
        candidate_ok = (
            candidate["error"] is None
            and candidate["code_units"] > 0
            and isinstance(candidate["code_sha256"], str)
            and len(candidate["code_sha256"]) == 64
            and type(candidate["cpu_ns"]) is int
            and candidate["cpu_ns"] > 0
            and candidate["outputs"] > 0
        )
        stock_ok = (
            stock["error"] is None
            and stock["code_units"] > 0
            and isinstance(stock["code_sha256"], str)
            and len(stock["code_sha256"]) == 64
            and type(stock["cpu_ns"]) is int
            and stock["cpu_ns"] > 0
            and stock["outputs"] > 0
        )
        duplicate = candidate_ok and stock_ok and (
            candidate["code_sha256"] == stock["code_sha256"]
        )
        admitted = candidate_ok and stock_ok and not duplicate
        if (
            row["normalized_inductor_duplicate"] is not duplicate
            or row["runtime_invention_admitted"] is not admitted
        ):
            raise IndependentLocalExactExecutionReject("native relation")
    summary = proposed.get("summary", {})
    if (
        summary.get("source_matches") != 17
        or summary.get("unique_bodies") != 3
        or summary.get("execution_rows") != 17
        or summary.get("candidate_exact_rows") != 17
        or summary.get("stock_exact_rows") != 17
        or summary.get("declared_outputs_checked") != 17
        or summary.get("causal_matches_after_remove_all") != 0
        or summary.get("native_compile_rows") != 3
        or summary.get("candidate_compile_successes") != 3
        or summary.get("stock_compile_successes") != 3
        or summary.get("normalized_inductor_duplicates")
        != sum(row["normalized_inductor_duplicate"] for row in native)
        or summary.get("runtime_inventions_admitted")
        != sum(row["runtime_invention_admitted"] for row in native)
    ):
        raise IndependentLocalExactExecutionReject("summary relation")
    if proposed.get("claims") != {
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
    }:
        raise IndependentLocalExactExecutionReject("claim boundary")


if __name__ == "__main__":
    result = expected_execution_ledger()
    summary = result["summary"]
    print(
        "FOUNDRY_INDEPENDENT_LOCAL_EXACT_EXECUTION"
        f" status={result['status']}"
        f" matches={summary['exact_matches_executed']}"
        f" unique={summary['unique_bodies_executed']}"
        f" outputs={summary['declared_outputs_checked']}"
        f" error={summary['maximum_abs_error']:.9g}"
        " native_dedup=false"
    )
