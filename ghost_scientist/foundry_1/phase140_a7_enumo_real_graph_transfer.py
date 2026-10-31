#!/usr/bin/env python3
"""Execute the pre-frozen A7 Enumo real-graph transfer falsification."""

from __future__ import annotations

import hashlib
import inspect
import json
import pathlib
import re
import sys
from collections import Counter
from dataclasses import dataclass
from typing import Any, TypeAlias

import torch
from torch.fx import Graph, GraphModule, Interpreter, Node

from enumo_tensor_rule_verifier import Call, Expr, Literal, Var, parse_rule
from independent_a7_real_graph_islands import extract as independent_extract
from independent_framework_runtime import (
    clone_tree,
    independent_assert,
    primary_compare,
)
from phase63_pareto_motif_calibration import old_repository, workloads
from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/A7_ENUMO_REAL_GRAPH_TRANSFER_PROTOCOL_V1.json"
)
FREEZE = HERE / "results/a7_enumo_real_graph_transfer_v1_freeze.json"
FEASIBILITY = HERE / "results/phase132_enumo_tensor_domain_feasibility.json"
FIXED_PROTOCOL = (
    HERE / "arm_adapter_fixtures/ENUMO_TENSOR_RULE_REUSE_PROTOCOL_V1.json"
)
WORKER_RESULT = HERE / "results/phase140_a7_enumo_real_graph_transfer_worker.json"
RESULT = HERE / "results/phase140_a7_enumo_real_graph_transfer.json"

MAPPING = {
    "aten.add.Tensor": "+",
    "aten.mul.Tensor": "*",
    "aten.relu.default": "relu",
}


@dataclass(frozen=True)
class Atom:
    name: str


@dataclass(frozen=True)
class TensorCall:
    operator: str
    arguments: tuple["Term", ...]


Term: TypeAlias = Atom | TensorCall


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def clean(value: str) -> str:
    return re.sub(r"[^a-z0-9_]+", "_", value.lower()).strip("_") or "empty"


def value_type(value: Any) -> str:
    if isinstance(value, torch.Tensor):
        return (
            f"tensor_r{len(value.shape)}_{clean(str(value.dtype))}_"
            f"{clean(str(value.layout))}"
        )
    return clean(type(value).__name__)


def leaf_record(value: Any) -> dict[str, str]:
    if isinstance(value, Node):
        return {
            "kind": "node",
            "name": value.name,
            "op": value.op,
            "target": str(value.target),
            "type": value_type(value.meta.get("val")),
        }
    return {
        "kind": "literal",
        "type": type(value).__name__,
        "value": repr(value),
    }


def leaf_name(value: Any) -> str:
    return "v_" + hashlib.sha256(
        canonical(leaf_record(value)).encode()
    ).hexdigest()[:16]


def valid_signature(node: Node) -> bool:
    target = str(node.target)
    if target == "aten.add.Tensor":
        return (
            len(node.args) == 2
            and set(node.kwargs) <= {"alpha"}
            and node.kwargs.get("alpha", 1) == 1
        )
    if target == "aten.mul.Tensor":
        return len(node.args) == 2 and not node.kwargs
    if target == "aten.relu.default":
        return len(node.args) == 1 and not node.kwargs
    return False


def serialize(term: Term) -> str:
    if isinstance(term, Atom):
        return term.name
    return (
        "("
        + term.operator
        + " "
        + " ".join(serialize(argument) for argument in term.arguments)
        + ")"
    )


def atom_count(term: Term) -> int:
    if isinstance(term, Atom):
        return 1
    return 1 + sum(atom_count(argument) for argument in term.arguments)


def primary_extract(graph: Graph) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    encoded: dict[Node, Term] = {}
    leaf_sources: dict[str, Any] = {}
    rows: list[dict[str, Any]] = []
    for node in graph.nodes:
        target = str(node.target)
        if node.op != "call_function" or target not in MAPPING:
            continue
        if not valid_signature(node):
            raise RuntimeError(f"mapped signature unsupported: {target}")
        arguments: list[Term] = []
        for value in node.args:
            if isinstance(value, Node) and value in encoded:
                arguments.append(encoded[value])
            else:
                name = leaf_name(value)
                prior = leaf_sources.setdefault(name, value)
                if prior is not value and leaf_record(prior) != leaf_record(value):
                    raise RuntimeError("leaf digest collision")
                arguments.append(Atom(name))
        term = TensorCall(MAPPING[target], tuple(arguments))
        encoded[node] = term
        rows.append(
            {
                "root_node": node.name,
                "target": target,
                "expression": serialize(term),
                "term": term,
            }
        )
    return rows, leaf_sources


def match(pattern: Expr, term: Term, bindings: dict[str, Term]) -> bool:
    if isinstance(pattern, Var):
        prior = bindings.get(pattern.name)
        if prior is None:
            bindings[pattern.name] = term
            return True
        return prior == term
    if isinstance(pattern, Literal):
        return False
    return (
        isinstance(term, TensorCall)
        and pattern.operator == term.operator
        and len(pattern.arguments) == len(term.arguments)
        and all(
            match(left, right, bindings)
            for left, right in zip(pattern.arguments, term.arguments, strict=True)
        )
    )


def substitute(pattern: Expr, bindings: dict[str, Term]) -> Term:
    if isinstance(pattern, Var):
        return bindings[pattern.name]
    if isinstance(pattern, Literal):
        raise RuntimeError("a literal RHS cannot be materialized without a matched literal")
    return TensorCall(
        pattern.operator,
        tuple(substitute(argument, bindings) for argument in pattern.arguments),
    )


def selected_rewrites(
    term: Term, rules: list[tuple[Expr, Expr]]
) -> tuple[int, list[tuple[int, Term]]]:
    matches = 0
    selected: list[tuple[int, Term]] = []
    source_cost = atom_count(term)
    source_serial = serialize(term)
    for index, (left, right) in enumerate(rules):
        bindings: dict[str, Term] = {}
        if not match(left, term, bindings):
            continue
        matches += 1
        try:
            candidate = substitute(right, bindings)
        except RuntimeError:
            continue
        cost = atom_count(candidate)
        serial = serialize(candidate)
        if cost < source_cost or (cost == source_cost and serial < source_serial):
            selected.append((index, candidate))
    return matches, selected


def evaluate(term: Term, leaves: dict[str, Any]) -> Any:
    if isinstance(term, Atom):
        return leaves[term.name]
    arguments = [evaluate(argument, leaves) for argument in term.arguments]
    if term.operator == "+":
        return arguments[0] + arguments[1]
    if term.operator == "*":
        return arguments[0] * arguments[1]
    if term.operator == "relu":
        return torch.relu(arguments[0])
    raise AssertionError("unknown operator")


class Capture(Interpreter):
    def __init__(self, module: GraphModule):
        super().__init__(module)
        self.values: dict[str, Any] = {}

    def run_node(self, node: Node) -> Any:
        value = super().run_node(node)
        self.values[node.name] = value
        return value


def captured_values(
    module: GraphModule, args: tuple[Any, ...], kwargs: dict[str, Any]
) -> dict[str, Any]:
    signature = inspect.signature(module.forward)
    bound = signature.bind(*clone_tree(args), **clone_tree(kwargs))
    bound.apply_defaults()
    runner = Capture(module)
    with torch.no_grad():
        runner.run(*bound.arguments.values())
    return runner.values


def concrete_leaves(
    sources: dict[str, Any], captures: dict[str, Any]
) -> dict[str, Any]:
    output = {}
    for name, source in sources.items():
        output[name] = (
            captures[source.name] if isinstance(source, Node) else source
        )
    return output


def worker() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    feasibility = json.loads(FEASIBILITY.read_text())
    fixed_protocol = json.loads(FIXED_PROTOCOL.read_text())
    learned_raw = feasibility["observed"]["learned_rules"]
    fixed_raw = fixed_protocol["strong_fixed_portfolio"]
    learned = [parse_rule(rule) for rule in learned_raw]
    fixed = [parse_rule(rule) for rule in fixed_raw]
    instantiated, unsupported = workloads()

    graphs = []
    operator_counts: Counter[str] = Counter()
    learned_matches = learned_selected = 0
    fixed_matches = fixed_selected = 0
    learned_receipts = []
    fixed_receipts = []
    max_error = 0.0
    for suite, workload in instantiated:
        family = workload["family"]
        artifact_id = f"{suite}:{family}"
        exported = torch.export.export(
            workload["model"],
            workload["args"],
            workload["kwargs"],
            strict=True,
        )
        module = exported.module()
        graph = module.graph
        counts = Counter(
            str(node.target)
            for node in graph.nodes
            if node.op == "call_function"
        )
        operator_counts.update(counts)
        primary, sources = primary_extract(graph)
        independent = independent_extract(graph)
        primary_projection = [
            {key: row[key] for key in ("root_node", "target", "expression")}
            for row in primary
        ]
        if primary_projection != independent:
            raise RuntimeError(f"island extractors disagree: {artifact_id}")

        row_learned_selected = []
        row_fixed_selected = []
        row_learned_matches = row_fixed_matches = 0
        for row in primary:
            count, selected = selected_rewrites(row["term"], learned)
            row_learned_matches += count
            row_learned_selected.extend(
                (row["root_node"], index, candidate)
                for index, candidate in selected
            )
            count, selected = selected_rewrites(row["term"], fixed)
            row_fixed_matches += count
            row_fixed_selected.extend(
                (row["root_node"], index, candidate)
                for index, candidate in selected
            )

        for ordinal in (1, 2, 3):
            seed = int.from_bytes(
                hashlib.sha256(
                    f"A7-TRANSFER:{artifact_id}:{ordinal}".encode()
                ).digest()[:8],
                "big",
            ) % (2**31)
            torch.manual_seed(seed)
            captures = captured_values(
                module, workload["args"], workload["kwargs"]
            )
            leaves = concrete_leaves(sources, captures)
            for portfolio, rows, receipts in (
                ("learned", row_learned_selected, learned_receipts),
                ("fixed", row_fixed_selected, fixed_receipts),
            ):
                for root_node, rule_index, candidate in rows:
                    expected = captures[root_node]
                    actual = evaluate(candidate, leaves)
                    comparison = primary_compare(expected, actual)
                    independent_assert(expected, actual)
                    max_error = max(max_error, comparison["max_abs_error"])
                    receipts.append(
                        {
                            "artifact_id": artifact_id,
                            "portfolio": portfolio,
                            "root_node": root_node,
                            "rule_index": rule_index,
                            "ordinal": ordinal,
                            "seed": seed,
                            "candidate": serialize(candidate),
                            "max_abs_error": comparison["max_abs_error"],
                            "expected_sha256": comparison["expected_sha256"],
                            "actual_sha256": comparison["actual_sha256"],
                            "alias_storage_checks_passed": comparison[
                                "alias_storage_checks_passed"
                            ],
                        }
                    )
        learned_matches += row_learned_matches
        learned_selected += len(row_learned_selected)
        fixed_matches += row_fixed_matches
        fixed_selected += len(row_fixed_selected)
        graphs.append(
            {
                "artifact_id": artifact_id,
                "family": family,
                "repository": workload.get(
                    "repository", old_repository(suite, family)
                ),
                "graph_sha256": hashlib.sha256(str(graph).encode()).hexdigest(),
                "operator_counts": dict(sorted(counts.items())),
                "eligible_roots": len(primary),
                "island_sha256": hashlib.sha256(
                    canonical(primary_projection).encode()
                ).hexdigest(),
                "learned_root_matches": row_learned_matches,
                "learned_selected_rewrites": len(row_learned_selected),
                "fixed_root_matches": row_fixed_matches,
                "fixed_selected_rewrites": len(row_fixed_selected),
            }
        )

    payload = {
        "version": "FOUNDRY_A7_ENUMO_REAL_GRAPH_TRANSFER_WORKER_V1",
        "graphs": graphs,
        "summary": {
            "graphs": len(graphs),
            "unique_operator_targets": len(operator_counts),
            "call_function_invocations": sum(operator_counts.values()),
            "unsupported_or_failed": len(unsupported),
            "eligible_graphs": sum(row["eligible_roots"] > 0 for row in graphs),
            "eligible_calls": sum(row["eligible_roots"] for row in graphs),
            "learned_rule_count": len(learned),
            "fixed_rule_count": len(fixed),
            "learned_root_matches": learned_matches,
            "learned_selected_rewrites": learned_selected,
            "fixed_root_matches": fixed_matches,
            "fixed_selected_rewrites": fixed_selected,
            "learned_concrete_receipts": len(learned_receipts),
            "fixed_concrete_receipts": len(fixed_receipts),
            "maximum_abs_error": max_error,
        },
        "learned_receipts": learned_receipts,
        "fixed_receipts": fixed_receipts,
        "unsupported_or_failed": unsupported,
        "validation_v6_accessed": False,
    }
    WORKER_RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE140_WORKER"
        f" graphs={len(graphs)} eligible={payload['summary']['eligible_calls']}"
        f" learned_matches={learned_matches}"
        f" learned_selected={learned_selected}"
        f" fixed_selected={fixed_selected}"
        f" error={max_error}"
    )


def main() -> None:
    if "--worker" in sys.argv:
        worker()
        return
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    providers_exact = all(
        sha(HERE / row["path"]) == row["sha256"]
        for row in protocol["provider_records"]
    )
    freeze_exact = (
        freeze["protocol_sha256"] == sha(PROTOCOL)
        and freeze["provider_records"] == protocol["provider_records"]
        and freeze["frozen_before_runner_implementation_or_execution"] is True
    )
    limits = {
        "wall_limit_seconds": 180,
        "cpu_limit_seconds": 160,
        "rss_limit_kib": 4_500_000,
    }
    receipt = run_metered_tree(
        [str(pathlib.Path(sys.executable).resolve()), str(__file__), "--worker"],
        cwd=HERE,
        environment={"PYTHONHASHSEED": "0"},
        **limits,
    )
    natural = (
        receipt["returncode"] == 0
        and receipt["termination"] == "natural"
        and receipt["process_group_reaped"] is True
        and "FOUNDRY_PHASE140_WORKER" in receipt["stdout_text"]
    )
    observed = (
        json.loads(WORKER_RESULT.read_text())
        if natural and WORKER_RESULT.exists()
        else {}
    )
    summary = observed.get("summary", {})
    learned_receipts = observed.get("learned_receipts", [])
    fixed_receipts = observed.get("fixed_receipts", [])
    checks = {
        "protocol_freeze_and_providers_exact": providers_exact and freeze_exact,
        "metered_worker_terminated_naturally": natural,
        "process_tree_cpu_rss_wall_accounted": (
            natural
            and receipt["observed_process_count"] >= 1
            and receipt["peak_group_rss_kib"] > 0
            and receipt["rusage_user_cpu_ns"]
            + receipt["rusage_system_cpu_ns"]
            > 0
        ),
        "complete_surface_exact": (
            summary.get("graphs") == 23
            and summary.get("unique_operator_targets") == 41
            and summary.get("call_function_invocations") == 337
            and summary.get("unsupported_or_failed") == 1
        ),
        "eligible_surface_exact": (
            summary.get("eligible_graphs") == 17
            and summary.get("eligible_calls") == 53
        ),
        "independent_extractors_agreed_all_graphs": (
            len(observed.get("graphs", [])) == 23
            and all(row.get("island_sha256") for row in observed.get("graphs", []))
        ),
        "frozen_rule_counts_exact": (
            summary.get("learned_rule_count") == 18
            and summary.get("fixed_rule_count") == 13
        ),
        "learned_root_matches_positive": summary.get(
            "learned_root_matches", 0
        )
        > 0,
        "learned_selected_rewrites_positive": summary.get(
            "learned_selected_rewrites", 0
        )
        > 0,
        "three_learned_receipts_per_selected": (
            len(learned_receipts)
            == 3 * summary.get("learned_selected_rewrites", -1)
        ),
        "three_fixed_receipts_per_selected": (
            len(fixed_receipts)
            == 3 * summary.get("fixed_selected_rewrites", -1)
        ),
        "all_selected_rewrites_concretely_correct": (
            all(
                row["max_abs_error"] <= 1.0e-5
                and row["alias_storage_checks_passed"]
                for row in learned_receipts + fixed_receipts
            )
            and summary.get("maximum_abs_error", float("inf")) <= 1.0e-5
        ),
        "validation_v6_unread": observed.get("validation_v6_accessed") is False,
    }
    passed = all(checks.values())
    payload = {
        "version": "FOUNDRY_A7_ENUMO_REAL_GRAPH_TRANSFER_RESULT_V1",
        "status": (
            "A7_ENUMO_REAL_GRAPH_TRANSFER_PASS"
            if passed
            else "A7_ENUMO_REAL_GRAPH_TRANSFER_REJECTED"
        ),
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "runner_records": [
            {"path": pathlib.Path(__file__).name, "sha256": sha(pathlib.Path(__file__))},
            {
                "path": "independent_a7_real_graph_islands.py",
                "sha256": sha(HERE / "independent_a7_real_graph_islands.py"),
            },
        ],
        "limits": limits,
        "receipt": receipt,
        "checks": checks,
        "observed": observed,
        "decision": {
            "full_A7_calibration_adapter_may_be_prefrozen": passed,
            "A7_production_integrated": False,
            "production_integrated_arms": 6,
            "fixed_portfolio_beaten": (
                summary.get("learned_selected_rewrites", 0)
                > summary.get("fixed_selected_rewrites", 0)
            ),
        },
        "claim_boundary": {
            "real_calibration_graph_transfer": passed,
            "empirical_observed_value_correctness_only": True,
            "universal_tensor_rewrite_soundness": False,
            "heldout_transfer": False,
            "production_integration": False,
            "validation_v6_accessed": False,
            "prospective_trial_authorized": False,
        },
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE140_A7_ENUMO_REAL_GRAPH_TRANSFER"
        f" status={payload['status']}"
        f" matches={summary.get('learned_root_matches', 0)}"
        f" selected={summary.get('learned_selected_rewrites', 0)}"
        f" receipts={len(learned_receipts)}"
        " integrated=6/10 prospective=false"
    )
    if not passed:
        raise RuntimeError(
            "A7 real-graph transfer failed: "
            + canonical({"failed": [key for key, value in checks.items() if not value]})
        )


if __name__ == "__main__":
    main()
