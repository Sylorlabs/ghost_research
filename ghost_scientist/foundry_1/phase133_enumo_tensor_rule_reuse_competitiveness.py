#!/usr/bin/env python3
"""Compare frozen learned tensor rules with a strong fixed portfolio."""

from __future__ import annotations

import collections
import hashlib
import itertools
import json
import pathlib
import sys
from dataclasses import dataclass
from typing import TypeAlias

from enumo_tensor_rule_verifier import (
    Call,
    Expr,
    Literal,
    Var,
    parse_rule,
)
from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE / "arm_adapter_fixtures/ENUMO_TENSOR_RULE_REUSE_PROTOCOL_V1.json"
)
FREEZE = HERE / "results/enumo_tensor_rule_reuse_v1_freeze.json"
FEASIBILITY = HERE / "results/phase132_enumo_tensor_domain_feasibility.json"
WORKER_RESULT = HERE / "results/phase133_enumo_tensor_rule_reuse_worker.json"
RESULT = HERE / "results/phase133_enumo_tensor_rule_reuse_competitiveness.json"


@dataclass(frozen=True)
class Atom:
    name: str


Term: TypeAlias = Atom | Literal | Call
Rule: TypeAlias = tuple[Expr, Expr]


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def serialize(term: Term) -> str:
    if isinstance(term, Atom):
        return term.name
    if isinstance(term, Literal):
        return "[" + ",".join(str(value) for value in term.lanes) + "]"
    return (
        "("
        + term.operator
        + " "
        + " ".join(serialize(argument) for argument in term.arguments)
        + ")"
    )


def atom_count(term: Term) -> int:
    if isinstance(term, (Atom, Literal)):
        return 1
    return 1 + sum(atom_count(argument) for argument in term.arguments)


def match(pattern: Expr, term: Term, bindings: dict[str, Term]) -> bool:
    if isinstance(pattern, Var):
        prior = bindings.get(pattern.name)
        if prior is None:
            bindings[pattern.name] = term
            return True
        return prior == term
    if isinstance(pattern, Literal):
        return pattern == term
    if not isinstance(term, Call):
        return False
    return (
        pattern.operator == term.operator
        and len(pattern.arguments) == len(term.arguments)
        and all(
            match(left, right, bindings)
            for left, right in zip(
                pattern.arguments, term.arguments, strict=True
            )
        )
    )


def substitute(pattern: Expr, bindings: dict[str, Term]) -> Term:
    if isinstance(pattern, Var):
        return bindings[pattern.name]
    if isinstance(pattern, Literal):
        return pattern
    return Call(
        pattern.operator,
        tuple(substitute(argument, bindings) for argument in pattern.arguments),
    )


def root_rewrites(term: Term, rules: list[Rule]) -> set[Term]:
    output: set[Term] = set()
    for left, right in rules:
        bindings: dict[str, Term] = {}
        if match(left, term, bindings):
            output.add(substitute(right, bindings))
    return output


def rewrites_once(term: Term, rules: list[Rule]) -> set[Term]:
    output = root_rewrites(term, rules)
    if isinstance(term, Call):
        for index, argument in enumerate(term.arguments):
            for replacement in rewrites_once(argument, rules):
                arguments = list(term.arguments)
                arguments[index] = replacement
                output.add(Call(term.operator, tuple(arguments)))
    current_atoms = atom_count(term)
    current_serial = serialize(term)
    return {
        candidate
        for candidate in output
        if atom_count(candidate) < current_atoms
        or (
            atom_count(candidate) == current_atoms
            and serialize(candidate) < current_serial
        )
    }


def optimize(term: Term, rules: list[Rule], cap: int) -> tuple[Term, int, bool]:
    seen = {term}
    pending = collections.deque([term])
    best = term
    while pending:
        current = pending.popleft()
        for candidate in rewrites_once(current, rules):
            if candidate in seen:
                continue
            seen.add(candidate)
            if len(seen) > cap:
                return best, len(seen), True
            pending.append(candidate)
            if (atom_count(candidate), serialize(candidate)) < (
                atom_count(best),
                serialize(best),
            ):
                best = candidate
    return best, len(seen), False


def literal(raw: str) -> Literal:
    values = tuple(int(value) for value in raw[1:-1].split(","))
    return Literal(values)  # type: ignore[arg-type]


def generate_exact_five(protocol: dict[str, object]) -> list[Term]:
    leaf_raw = protocol["held_out_generator"]["ordered_leaf_forms"]
    by_size: dict[int, list[Term]] = {
        1: [
            Atom(raw) if raw in {"a", "b"} else literal(raw)
            for raw in leaf_raw
        ]
    }
    for size in range(2, 6):
        terms: list[Term] = [
            Call("relu", (child,)) for child in by_size[size - 1]
        ]
        for left_size in range(1, size - 1):
            right_size = size - 1 - left_size
            for operator in ("+", "*"):
                terms.extend(
                    Call(operator, (left, right))
                    for left in by_size[left_size]
                    for right in by_size[right_size]
                )
        by_size[size] = terms
    output = by_size[5]
    if len(output) != len(set(output)):
        raise RuntimeError("held-out generator produced duplicates")
    return output


def evaluate(term: Term, values: dict[str, int], lane: int) -> int | None:
    if isinstance(term, Atom):
        return values[term.name]
    if isinstance(term, Literal):
        return term.lanes[lane]
    arguments = [evaluate(argument, values, lane) for argument in term.arguments]
    if any(value is None for value in arguments):
        return None
    concrete = [int(value) for value in arguments]
    if term.operator == "+":
        result = concrete[0] + concrete[1]
        return result if -(2**31) <= result < 2**31 else None
    if term.operator == "*":
        result = concrete[0] * concrete[1]
        return result if -(2**31) <= result < 2**31 else None
    if term.operator == "relu":
        return max(concrete[0], 0)
    raise AssertionError("unknown generated operator")


def semantically_equal(
    left: Term, right: Term, scalar_domain: tuple[int, ...]
) -> bool:
    for a, b in itertools.product(scalar_domain, repeat=2):
        values = {"a": a, "b": b}
        for lane in range(4):
            if evaluate(left, values, lane) != evaluate(right, values, lane):
                return False
    return True


def worker() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    feasibility = json.loads(FEASIBILITY.read_text())
    learned_rules = [
        parse_rule(rule) for rule in feasibility["observed"]["learned_rules"]
    ]
    fixed_rules = [
        parse_rule(rule) for rule in protocol["strong_fixed_portfolio"]
    ]
    held_out = generate_exact_five(protocol)
    cap = protocol["optimization"]["maximum_unique_states_per_expression_per_portfolio"]
    scalar_domain = tuple(
        protocol["semantic_validation"]["independent_scalar_domain"]
    )
    learned_wins: list[dict[str, object]] = []
    fixed_wins: list[dict[str, object]] = []
    ties = 0
    learned_reductions = 0
    fixed_reductions = 0
    max_learned_states = 0
    max_fixed_states = 0
    state_cap_hits = 0
    semantic_failures: list[dict[str, str]] = []
    for expression in held_out:
        learned, learned_states, learned_capped = optimize(
            expression, learned_rules, cap
        )
        fixed, fixed_states, fixed_capped = optimize(
            expression, fixed_rules, cap
        )
        max_learned_states = max(max_learned_states, learned_states)
        max_fixed_states = max(max_fixed_states, fixed_states)
        state_cap_hits += int(learned_capped) + int(fixed_capped)
        input_atoms = atom_count(expression)
        learned_atoms = atom_count(learned)
        fixed_atoms = atom_count(fixed)
        learned_reductions += int(learned_atoms < input_atoms)
        fixed_reductions += int(fixed_atoms < input_atoms)
        row = {
            "input": serialize(expression),
            "learned": serialize(learned),
            "fixed": serialize(fixed),
            "learned_atoms": learned_atoms,
            "fixed_atoms": fixed_atoms,
        }
        if learned_atoms < fixed_atoms:
            if len(learned_wins) < 12:
                learned_wins.append(row)
        elif fixed_atoms < learned_atoms:
            if len(fixed_wins) < 12:
                fixed_wins.append(row)
        else:
            ties += 1
        if not semantically_equal(expression, learned, scalar_domain):
            semantic_failures.append(
                {"portfolio": "learned", "input": serialize(expression)}
            )
        if not semantically_equal(expression, fixed, scalar_domain):
            semantic_failures.append(
                {"portfolio": "fixed", "input": serialize(expression)}
            )
    learned_strict_count = sum(
        1
        for expression in held_out
        if atom_count(optimize(expression, learned_rules, cap)[0])
        < atom_count(optimize(expression, fixed_rules, cap)[0])
    )
    fixed_strict_count = len(held_out) - learned_strict_count - ties
    payload = {
        "version": "FOUNDRY_ENUMO_TENSOR_RULE_REUSE_WORKER_V1",
        "held_out_expression_count": len(held_out),
        "learned_rule_count": len(learned_rules),
        "fixed_rule_count": len(fixed_rules),
        "learned_reduction_count": learned_reductions,
        "fixed_reduction_count": fixed_reductions,
        "learned_strict_wins": learned_strict_count,
        "fixed_strict_wins": fixed_strict_count,
        "atom_cost_ties": ties,
        "state_cap_hits": state_cap_hits,
        "max_learned_states": max_learned_states,
        "max_fixed_states": max_fixed_states,
        "semantic_failures": semantic_failures,
        "learned_win_examples": learned_wins,
        "fixed_win_examples": fixed_wins,
        "validation_v6_accessed": False,
    }
    WORKER_RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE133_WORKER"
        f" heldout={len(held_out)}"
        f" learned_wins={learned_strict_count}"
        f" fixed_wins={fixed_strict_count}"
        f" ties={ties}"
        f" caps={state_cap_hits}"
    )


def main() -> None:
    if "--worker" in sys.argv:
        worker()
        return
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    frozen_inputs_exact = all(
        sha(HERE / row["path"]) == row["sha256"]
        for row in protocol["frozen_inputs"]
    )
    freeze_exact = (
        freeze["protocol_sha256"] == sha(PROTOCOL)
        and freeze["frozen_inputs"] == protocol["frozen_inputs"]
        and freeze["frozen_before_reuse_runner_implementation_or_execution"]
        is True
    )
    limits = {
        "wall_limit_seconds": 180,
        "cpu_limit_seconds": 160,
        "rss_limit_kib": 1_500_000,
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
        and "FOUNDRY_PHASE133_WORKER" in receipt["stdout_text"]
    )
    observed = (
        json.loads(WORKER_RESULT.read_text())
        if natural and WORKER_RESULT.exists()
        else {}
    )
    checks = {
        "protocol_and_freeze_exact": frozen_inputs_exact and freeze_exact,
        "metered_worker_terminated_naturally": natural,
        "process_tree_cpu_rss_wall_accounted": (
            natural
            and receipt["observed_process_count"] >= 1
            and receipt["peak_group_rss_kib"] > 0
            and receipt["rusage_user_cpu_ns"]
            + receipt["rusage_system_cpu_ns"]
            > 0
        ),
        "all_held_out_expressions_executed": (
            observed.get("held_out_expression_count") == 3339
        ),
        "frozen_portfolio_sizes_exact": (
            observed.get("learned_rule_count") == 18
            and observed.get("fixed_rule_count") == 13
        ),
        "no_state_cap_reached": observed.get("state_cap_hits") == 0,
        "all_selected_outputs_independently_sound": (
            observed.get("semantic_failures") == []
        ),
        "outcome_partition_complete": (
            observed.get("learned_strict_wins", -1)
            + observed.get("fixed_strict_wins", -1)
            + observed.get("atom_cost_ties", -1)
            == 3339
        ),
        "validation_v6_unread": observed.get("validation_v6_accessed") is False,
    }
    learned_beats_fixed = observed.get("learned_strict_wins", 0) > 0
    operationally_valid = all(checks.values())
    payload = {
        "version": "FOUNDRY_ENUMO_TENSOR_RULE_REUSE_RESULT_V1",
        "status": (
            "ENUMO_TENSOR_RULE_REUSE_BEATS_FIXED_ON_HELD_OUT"
            if operationally_valid and learned_beats_fixed
            else (
                "ENUMO_TENSOR_RULE_REUSE_DOES_NOT_BEAT_FIXED"
                if operationally_valid
                else "ENUMO_TENSOR_RULE_REUSE_AUDIT_INVALID"
            )
        ),
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "runner_sha256": sha(pathlib.Path(__file__)),
        "limits": limits,
        "receipt": receipt,
        "checks": checks,
        "operationally_valid": operationally_valid,
        "protocol_acceptance": {
            "learned_strict_wins_required": 1,
            "learned_strict_wins_observed": observed.get(
                "learned_strict_wins", 0
            ),
            "accepted": operationally_valid and learned_beats_fixed,
        },
        "observed": observed,
        "claim_boundary": {
            "generated_not_real_artifacts": True,
            "full_tensor_graph_language": False,
            "full_23_graph_adapter": False,
            "is_frozen_boolean_A7": False,
            "A7_production_integrated": False,
            "production_integrated_arms": 6,
            "P1_advance": False,
            "P3_integration_advance": False,
            "validation_v6_accessed": False,
            "prospective_trial_authorized": False,
        },
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE133_ENUMO_TENSOR_RULE_REUSE"
        f" status={payload['status']}"
        f" learned_wins={observed.get('learned_strict_wins', 0)}"
        f" fixed_wins={observed.get('fixed_strict_wins', 0)}"
        f" ties={observed.get('atom_cost_ties', 0)}"
        " integrated=6/10 prospective=false"
    )


if __name__ == "__main__":
    main()
