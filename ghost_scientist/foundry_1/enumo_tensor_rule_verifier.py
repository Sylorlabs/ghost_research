#!/usr/bin/env python3
"""Independent parser and expanded-domain verifier for Enumo tensor rules."""

from __future__ import annotations

import itertools
import re
from dataclasses import dataclass
from typing import TypeAlias


I32_MIN = -(2**31)
I32_MAX = 2**31 - 1
VARIABLE = re.compile(r"\?[A-Za-z][A-Za-z0-9_]*\Z")
INTEGER = re.compile(r"-?(?:0|[1-9][0-9]*)\Z")


class RuleError(ValueError):
    """A rule is syntactically invalid, unsafe, or semantically false."""


@dataclass(frozen=True)
class Var:
    name: str


@dataclass(frozen=True)
class Literal:
    lanes: tuple[int, int, int, int]


@dataclass(frozen=True)
class Call:
    operator: str
    arguments: tuple["Expr", ...]


Expr: TypeAlias = Var | Literal | Call


def _tokenize(raw: str) -> list[str]:
    tokens: list[str] = []
    index = 0
    while index < len(raw):
        char = raw[index]
        if char.isspace():
            index += 1
        elif char in "()":
            tokens.append(char)
            index += 1
        elif char == "[":
            end = raw.find("]", index + 1)
            if end < 0:
                raise RuleError("unterminated vector literal")
            token = raw[index : end + 1]
            if any(mark in token[1:-1] for mark in "[]()"):
                raise RuleError("nested punctuation in vector literal")
            tokens.append(token)
            index = end + 1
        else:
            end = index + 1
            while end < len(raw) and not raw[end].isspace() and raw[end] not in "()[]":
                end += 1
            tokens.append(raw[index:end])
            index = end
    return tokens


def _literal(token: str) -> Literal:
    if not (token.startswith("[") and token.endswith("]")):
        raise RuleError(f"unsupported atom: {token!r}")
    parts = token[1:-1].split(",")
    if len(parts) != 4 or any(not INTEGER.fullmatch(part) for part in parts):
        raise RuleError("vector literal must contain exactly four canonical integers")
    values = tuple(int(part) for part in parts)
    if any(value < I32_MIN or value > I32_MAX for value in values):
        raise RuleError("vector literal lane is outside signed i32")
    return Literal(values)  # type: ignore[arg-type]


def _parse_expr(tokens: list[str], position: int = 0) -> tuple[Expr, int]:
    if position >= len(tokens):
        raise RuleError("missing expression")
    token = tokens[position]
    if token == ")":
        raise RuleError("unexpected closing parenthesis")
    if token != "(":
        if VARIABLE.fullmatch(token):
            return Var(token), position + 1
        return _literal(token), position + 1
    if position + 1 >= len(tokens):
        raise RuleError("missing operator")
    operator = tokens[position + 1]
    arity = {"+": 2, "*": 2, "relu": 1}.get(operator)
    if arity is None:
        raise RuleError(f"unsupported operator: {operator!r}")
    arguments: list[Expr] = []
    cursor = position + 2
    for _ in range(arity):
        argument, cursor = _parse_expr(tokens, cursor)
        arguments.append(argument)
    if cursor >= len(tokens) or tokens[cursor] != ")":
        raise RuleError(f"operator {operator!r} has malformed arity")
    return Call(operator, tuple(arguments)), cursor + 1


def parse_expr(raw: str) -> Expr:
    tokens = _tokenize(raw)
    expression, position = _parse_expr(tokens)
    if position != len(tokens):
        raise RuleError("trailing tokens")
    return expression


def parse_rule(raw: str) -> tuple[Expr, Expr]:
    if raw.count("==>") != 1:
        raise RuleError("rule must contain exactly one directed delimiter")
    left_raw, right_raw = raw.split("==>")
    if not left_raw.strip() or not right_raw.strip():
        raise RuleError("rule side is empty")
    left = parse_expr(left_raw.strip())
    right = parse_expr(right_raw.strip())
    left_vars = variables(left)
    right_vars = variables(right)
    if not right_vars <= left_vars:
        raise RuleError("right-hand side introduces an unbound variable")
    if left == right:
        raise RuleError("identity rewrite is not a useful learned rule")
    return left, right


def variables(expression: Expr) -> set[str]:
    if isinstance(expression, Var):
        return {expression.name}
    if isinstance(expression, Literal):
        return set()
    output: set[str] = set()
    for argument in expression.arguments:
        output.update(variables(argument))
    return output


def _checked(value: int) -> int | None:
    return value if I32_MIN <= value <= I32_MAX else None


def evaluate_lane(
    expression: Expr, assignments: dict[str, int], lane: int
) -> int | None:
    if isinstance(expression, Var):
        return assignments[expression.name]
    if isinstance(expression, Literal):
        return expression.lanes[lane]
    values = [
        evaluate_lane(argument, assignments, lane)
        for argument in expression.arguments
    ]
    if any(value is None for value in values):
        return None
    concrete = [int(value) for value in values]
    if expression.operator == "+":
        return _checked(concrete[0] + concrete[1])
    if expression.operator == "*":
        return _checked(concrete[0] * concrete[1])
    if expression.operator == "relu":
        return max(concrete[0], 0)
    raise AssertionError("parser admitted an unknown operator")


def verify_rule(raw: str, scalar_domain: tuple[int, ...]) -> dict[str, object]:
    left, right = parse_rule(raw)
    names = sorted(variables(left) | variables(right))
    assignments_checked = 0
    lane_checks = 0
    defined_lane_checks = 0
    for values in itertools.product(scalar_domain, repeat=len(names)):
        assignments = dict(zip(names, values, strict=True))
        assignments_checked += 1
        for lane in range(4):
            left_value = evaluate_lane(left, assignments, lane)
            right_value = evaluate_lane(right, assignments, lane)
            lane_checks += 1
            if left_value is not None or right_value is not None:
                defined_lane_checks += 1
            if left_value != right_value:
                raise RuleError(
                    "semantic counterexample:"
                    f" assignments={assignments} lane={lane}"
                    f" lhs={left_value} rhs={right_value}"
                )
    if defined_lane_checks == 0:
        raise RuleError("rule has no defined expanded-domain observation")
    return {
        "rule": raw,
        "variables": names,
        "assignments_checked": assignments_checked,
        "lane_checks": lane_checks,
        "defined_lane_checks": defined_lane_checks,
        "passed": True,
    }


def hostile_parser_selftest() -> dict[str, object]:
    hostile = {
        "unknown_operator": "(sigmoid ?a) ==> ?a",
        "wrong_binary_arity": "(+ ?a) ==> ?a",
        "wrong_unary_arity": "(relu ?a ?b) ==> ?a",
        "new_rhs_variable": "?a ==> (+ ?a ?b)",
        "wrong_literal_width": "[0,0,0] ==> [0,0,0]",
        "trailing_tokens": "?a ==> ?a [0,0,0,0]",
        "multiple_delimiters": "?a ==> ?a ==> ?a",
        "untrue_rule": "(+ ?a ?a) ==> ?a",
        "identity_rule": "?a ==> ?a",
    }
    rejected: dict[str, str] = {}
    for name, rule in hostile.items():
        try:
            verify_rule(rule, (-3, -2, -1, 0, 1, 2, 3))
        except RuleError as error:
            rejected[name] = str(error)
    return {
        "hostile_cases": len(hostile),
        "rejected_cases": len(rejected),
        "all_rejected": set(rejected) == set(hostile),
        "rejections": rejected,
    }


def verify_rules(
    rules: list[str], scalar_domain: tuple[int, ...]
) -> dict[str, object]:
    checks = [verify_rule(rule, scalar_domain) for rule in rules]
    return {
        "rules_checked": len(checks),
        "all_rules_passed": len(checks) == len(rules) and all(
            check["passed"] for check in checks
        ),
        "total_assignments_checked": sum(
            int(check["assignments_checked"]) for check in checks
        ),
        "total_lane_checks": sum(int(check["lane_checks"]) for check in checks),
        "rule_checks": checks,
    }

