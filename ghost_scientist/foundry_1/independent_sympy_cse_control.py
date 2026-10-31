#!/usr/bin/env python3
"""Stdlib-only validation of serialized SymPy CSE control outputs."""

from __future__ import annotations

import ast
import cmath
import copy
import math


class IndependentReject(ValueError):
    """The serialized control result violated the frozen boundary."""


TOP_KEYS = {
    "version",
    "status",
    "protocol_sha256",
    "freeze_sha256",
    "amendment_sha256",
    "amendment_freeze_sha256",
    "initial_infrastructure_failure",
    "identity",
    "source_records",
    "distribution_integrity",
    "official_suite",
    "baseline_fixture",
    "renamed_reordered_fixture",
    "gates",
    "candidate_fourth_P1_control",
    "independent_semantic_check_pending",
    "process_tree_resource_check_pending",
    "P1_complete",
    "production_integrated_arms",
    "A6_satisfied",
    "A8_satisfied",
    "validation_v6_accessed",
    "prospective_trial_authorized",
    "claim_boundary",
}
FIXTURE_KEYS = {"expressions", "replacements", "reduced", "sample_points"}
EXPECTED_SOURCES = [
    {
        "path": "sympy/simplify/cse_main.py",
        "git_blob_sha1": "e03789b48f770761eb0130c8469275a47e31a702",
        "sha256": "8434d94f07a3c6ca4af33c3ed8b5d91c5f6b2ff14cacaddbc98a08b00fd8ae82",
    },
    {
        "path": "sympy/simplify/cse_opts.py",
        "git_blob_sha1": "36a59857411de740ae47423442af88b118a3395d",
        "sha256": "65309a39d3ab82d89f5b1426173ca782b2eaf6ec3307205d8924b9984f830e81",
    },
    {
        "path": "sympy/simplify/tests/test_cse.py",
        "git_blob_sha1": "4e3955252ee65b1f7d949c23822508b7ef0a0dd9",
        "sha256": "b1ab3afa34651da67a8dd897a064c2e7604d66fb94b5a629b484353fee493b4d",
    },
]


def _exact_keys(value: dict, expected: set[str], label: str) -> None:
    if type(value) is not dict or set(value) != expected:
        raise IndependentReject(f"{label} keys are not exact")


def parse_result(value: object) -> dict:
    if type(value) is not dict:
        raise IndependentReject("result must be object")
    _exact_keys(value, TOP_KEYS, "result")
    if not (
        value["version"] == "FOUNDRY_SYMPY_CSE_SOURCE_CONTROL_V1"
        and value["status"] == "SYMPY_CSE_SOURCE_CONTROL_PRELIMINARY_PASS"
        and value["identity"]
        == {
            "distribution": "sympy",
            "version": "1.13.1",
            "official_tag": "sympy-1.13.1",
        }
        and value["source_records"] == EXPECTED_SOURCES
        and value["distribution_integrity"]["all_hashed_files_exact"] is True
        and value["distribution_integrity"]["hashed_files_verified"] >= 1000
        and value["distribution_integrity"]["record_sha256"]
        == "7d91c5fcc7f1809f944bba8532229c110d81270a640c611c4b08046b3c38c547"
        and value["official_suite"]["accepted"] is True
        and value["official_suite"]["failures"] == 0
        and value["official_suite"]["errors"] == 0
        and value["official_suite"]["xpassed"] == 0
        and value["official_suite"]["passed"] == 53
        and value["official_suite"]["source_declared_xfails"] == 8
        and value["official_suite"]["pytest_classified_xfails"] == 8
        and value["official_suite"]["accepted_expected_outcomes"] == 61
        and value["initial_infrastructure_failure"]["preserved"] is True
        and value["initial_infrastructure_failure"][
            "test_outcome_observed"
        ]
        is False
        and value["candidate_fourth_P1_control"] is True
        and value["independent_semantic_check_pending"] is True
        and value["process_tree_resource_check_pending"] is True
        and value["P1_complete"] is False
        and value["production_integrated_arms"] == 6
        and value["A6_satisfied"] is False
        and value["A8_satisfied"] is False
        and value["validation_v6_accessed"] is False
        and value["prospective_trial_authorized"] is False
    ):
        raise IndependentReject("result boundary changed")
    for name in ["baseline_fixture", "renamed_reordered_fixture"]:
        fixture = value[name]
        _exact_keys(fixture, FIXTURE_KEYS, name)
        if (
            type(fixture["expressions"]) is not list
            or type(fixture["replacements"]) is not list
            or type(fixture["reduced"]) is not list
            or len(fixture["expressions"]) != len(fixture["reduced"])
            or not fixture["sample_points"]
        ):
            raise IndependentReject(f"{name} structure invalid")
        for row in fixture["replacements"]:
            _exact_keys(row, {"symbol", "expression"}, "replacement")
    return copy.deepcopy(value)


def evaluate(
    text: str, environment: dict[str, float | complex]
) -> complex:
    node = ast.parse(text, mode="eval").body

    def visit(current: ast.AST) -> complex:
        if isinstance(current, ast.Constant) and type(current.value) in {
            int,
            float,
        }:
            return complex(current.value)
        if isinstance(current, ast.Name) and current.id in environment:
            return complex(environment[current.id])
        if isinstance(current, ast.UnaryOp) and isinstance(
            current.op, (ast.UAdd, ast.USub)
        ):
            value = visit(current.operand)
            return value if isinstance(current.op, ast.UAdd) else -value
        if isinstance(current, ast.BinOp):
            left, right = visit(current.left), visit(current.right)
            if isinstance(current.op, ast.Add):
                return left + right
            if isinstance(current.op, ast.Sub):
                return left - right
            if isinstance(current.op, ast.Mult):
                return left * right
            if isinstance(current.op, ast.Div):
                return left / right
            if isinstance(current.op, ast.Pow):
                return left**right
        if (
            isinstance(current, ast.Call)
            and isinstance(current.func, ast.Name)
            and current.func.id in {"sqrt", "sin", "cos"}
            and len(current.args) == 1
            and not current.keywords
        ):
            return getattr(cmath, current.func.id)(visit(current.args[0]))
        raise IndependentReject(f"unsupported expression node: {ast.dump(current)}")

    value = visit(node)
    if not (math.isfinite(value.real) and math.isfinite(value.imag)):
        raise IndependentReject("non-finite fixture value")
    return value


def validate_fixture(fixture: dict, tolerance: float) -> dict[str, object]:
    maximum_error = 0.0
    comparisons = 0
    for point in fixture["sample_points"]:
        if (
            type(point) is not dict
            or not point
            or any(type(value) not in {int, float} for value in point.values())
        ):
            raise IndependentReject("invalid sample point")
        expected = [
            evaluate(text, dict(point)) for text in fixture["expressions"]
        ]
        environment = dict(point)
        for row in fixture["replacements"]:
            symbol = row["symbol"]
            if (
                type(symbol) is not str
                or not symbol.isidentifier()
                or symbol in environment
            ):
                raise IndependentReject("invalid replacement symbol")
            environment[symbol] = evaluate(row["expression"], environment)
        observed = [
            evaluate(text, environment) for text in fixture["reduced"]
        ]
        for left, right in zip(expected, observed, strict=True):
            error = abs(left - right)
            maximum_error = max(maximum_error, error)
            comparisons += 1
            if error > tolerance:
                raise IndependentReject(
                    f"numeric reconstruction error {error} exceeds {tolerance}"
                )
    return {
        "comparisons": comparisons,
        "maximum_absolute_error": maximum_error,
        "passed": True,
    }


def validate_result(value: object, *, tolerance: float) -> dict[str, object]:
    parsed = parse_result(value)
    baseline = validate_fixture(parsed["baseline_fixture"], tolerance)
    renamed = validate_fixture(
        parsed["renamed_reordered_fixture"], tolerance
    )
    if len(parsed["baseline_fixture"]["replacements"]) != len(
        parsed["renamed_reordered_fixture"]["replacements"]
    ):
        raise IndependentReject("metamorphic replacement count changed")
    return {
        "baseline": baseline,
        "renamed_reordered": renamed,
        "replacement_count": len(
            parsed["baseline_fixture"]["replacements"]
        ),
        "replacement_count_preserved": True,
        "passed": True,
    }
