#!/usr/bin/env python3
"""Independent verifier for contained Ghost Ruler v3 candidate output.

This module intentionally does not import the constructor, candidate, target
generator, or e-graph control.  It reparses both expressions, computes exact
integer-polynomial normal forms, and exhaustively enumerates semantic classes
to prove the first reachable operator cost in the declared grammar.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from collections.abc import Mapping, Sequence


Tree = str | tuple[str, "Tree", "Tree"]
Meaning = tuple[tuple[tuple[int, int, int], int], ...]
OPS = frozenset(("add", "mul", "sub"))
LEAVES = ("x", "y", "z", "0", "1", "2")
RESULT = re.compile(
    r"GHOST_RULER_TOOL_V3"
    r" grammar_sha256=([0-9a-f]{64})"
    r" input_sha256=([0-9a-f]{64})"
    r" before=([0-9]+)"
    r" prepass=([0-9]+)"
    r" after=([0-9]+)"
    r" prepass_steps=([0-9]+)"
    r" prepass_attempts=([0-9]+)"
    r" enodes=([0-9]+)"
    r" ematches=([0-9]+)"
    r" iterations=([0-9]+)"
    r" saturated=(true|false)"
    r" expr=(.+)"
)
CONTROL_RESULT = re.compile(
    r"GHOST_POLY_CONTROL_V3"
    r" method=([a-z_]+)"
    r" before=([0-9]+)"
    r" after=([0-9]+)"
    r" work=([0-9]+)"
    r" unit=([a-z_]+)"
    r" prepass_steps=([0-9]+)"
    r" saturated=(true|false)"
    r" expr=(.+)"
)


class VerificationError(ValueError):
    pass


def parse(text: str) -> Tree:
    tokens = text.replace("(", " ( ").replace(")", " ) ").split()
    cursor = 0

    def one() -> Tree:
        nonlocal cursor
        if cursor >= len(tokens):
            raise VerificationError("expression ended early")
        token = tokens[cursor]
        cursor += 1
        if token != "(":
            if token == ")" or token not in LEAVES:
                raise VerificationError("invalid leaf")
            return token
        if cursor >= len(tokens) or tokens[cursor] not in OPS:
            raise VerificationError("invalid operator")
        operator = tokens[cursor]
        cursor += 1
        left = one()
        right = one()
        if cursor >= len(tokens) or tokens[cursor] != ")":
            raise VerificationError("unclosed expression")
        cursor += 1
        return (operator, left, right)

    tree = one()
    if cursor != len(tokens):
        raise VerificationError("trailing expression tokens")
    return tree


def render(tree: Tree) -> str:
    if isinstance(tree, str):
        return tree
    return f"({tree[0]} {render(tree[1])} {render(tree[2])})"


def operators(tree: Tree) -> int:
    if isinstance(tree, str):
        return 0
    return 1 + operators(tree[1]) + operators(tree[2])


def frozen(values: Mapping[tuple[int, int, int], int]) -> Meaning:
    return tuple(sorted((power, coefficient) for power, coefficient in values.items() if coefficient))


def constant(value: int) -> Meaning:
    return () if value == 0 else (((0, 0, 0), value),)


def variable(index: int) -> Meaning:
    power = [0, 0, 0]
    power[index] = 1
    return ((tuple(power), 1),)


def plus(left: Meaning, right: Meaning, scale: int = 1) -> Meaning:
    result = dict(left)
    for power, coefficient in right:
        result[power] = result.get(power, 0) + scale * coefficient
    return frozen(result)


def times(left: Meaning, right: Meaning) -> Meaning:
    result: dict[tuple[int, int, int], int] = {}
    for left_power, left_coefficient in left:
        for right_power, right_coefficient in right:
            power = (
                left_power[0] + right_power[0],
                left_power[1] + right_power[1],
                left_power[2] + right_power[2],
            )
            result[power] = result.get(power, 0) + left_coefficient * right_coefficient
    return frozen(result)


def normalize(tree: Tree) -> Meaning:
    if isinstance(tree, str):
        if tree in ("x", "y", "z"):
            return variable(("x", "y", "z").index(tree))
        return constant(int(tree))
    operator, left_tree, right_tree = tree
    left = normalize(left_tree)
    right = normalize(right_tree)
    if operator == "add":
        return plus(left, right)
    if operator == "sub":
        return plus(left, right, -1)
    return times(left, right)


def exact_minimum(target: Meaning, max_cost: int = 4) -> tuple[int | None, list[int]]:
    """Return first exact semantic layer containing target.

    Each layer contains meanings whose cheapest expression has exactly that
    many binary operators.  Thus first appearance is a global optimum within
    the finite operator/leaf grammar, not a rewrite-system local optimum.
    """
    layers: list[set[Meaning]] = [set() for _ in range(max_cost + 1)]
    layers[0] = {normalize(parse(leaf)) for leaf in LEAVES}
    counts = [len(layers[0])]
    if target in layers[0]:
        return 0, counts
    discovered = set(layers[0])
    for cost in range(1, max_cost + 1):
        layer = layers[cost]
        for left_cost in range(cost):
            right_cost = cost - 1 - left_cost
            for left in layers[left_cost]:
                for right in layers[right_cost]:
                    for meaning in (
                        plus(left, right),
                        times(left, right),
                        plus(left, right, -1),
                    ):
                        if meaning not in discovered:
                            layer.add(meaning)
        counts.append(len(layer))
        if target in layer:
            return cost, counts
        discovered.update(layer)
    return None, counts


def verify(
    line: str,
    source_text: str,
    expected_grammar_sha: str,
    *,
    max_cost: int = 4,
) -> tuple[int, list[int]]:
    if line.endswith("\n"):
        line = line[:-1]
    if "\n" in line or "\r" in line:
        raise VerificationError("candidate emitted extra lines")
    match = RESULT.fullmatch(line)
    if match is None:
        raise VerificationError("candidate record shape is invalid")
    (
        grammar_sha,
        input_sha,
        before_text,
        prepass_text,
        after_text,
        steps_text,
        attempts_text,
        enodes_text,
        ematches_text,
        iterations_text,
        _saturated,
        output_text,
    ) = match.groups()
    if grammar_sha != expected_grammar_sha:
        raise VerificationError("grammar digest mismatch")

    source = parse(source_text)
    canonical_source = render(source)
    expected_input_sha = hashlib.sha256(canonical_source.encode("utf-8")).hexdigest()
    if input_sha != expected_input_sha:
        raise VerificationError("input digest mismatch")
    output = parse(output_text)

    before = int(before_text)
    prepass = int(prepass_text)
    after = int(after_text)
    steps = int(steps_text)
    attempts = int(attempts_text)
    enodes = int(enodes_text)
    ematches = int(ematches_text)
    iterations = int(iterations_text)
    if before != operators(source) or after != operators(output):
        raise VerificationError("reported operator cost is false")
    if not (after <= prepass <= before):
        raise VerificationError("cost trajectory is impossible")
    if steps > 4096 or attempts < steps or not (1 <= enodes <= 5000):
        raise VerificationError("candidate work metadata is outside its contract")
    if ematches < 0 or not (1 <= iterations <= 12):
        raise VerificationError("e-graph work metadata is outside its contract")

    target = normalize(source)
    if normalize(output) != target:
        raise VerificationError("candidate changed exact polynomial semantics")
    minimum, counts = exact_minimum(target, max_cost=max_cost)
    if minimum is None:
        raise VerificationError("global optimum was not found within proof bound")
    if after != minimum:
        raise VerificationError("candidate result is not globally minimal")
    return minimum, counts


def verify_control(line: str, source_text: str) -> tuple[str, int]:
    if line.endswith("\n"):
        line = line[:-1]
    if "\n" in line or "\r" in line:
        raise VerificationError("control emitted extra lines")
    match = CONTROL_RESULT.fullmatch(line)
    if match is None:
        raise VerificationError("control record shape is invalid")
    method, before_text, after_text, _work, _unit, _steps, _saturated, output_text = (
        match.groups()
    )
    source = parse(source_text)
    output = parse(output_text)
    before = int(before_text)
    after = int(after_text)
    if before != operators(source) or after != operators(output):
        raise VerificationError("control operator cost is false")
    if normalize(source) != normalize(output):
        raise VerificationError("control changed exact polynomial semantics")
    if method == "brute_force":
        minimum, _counts = exact_minimum(normalize(source), max_cost=4)
        if minimum is None or after != minimum:
            raise VerificationError("brute-force control is not globally minimal")
    return method, after


def selftest() -> None:
    grammar_sha = "a" * 64
    source = "(add (mul x y) (mul x z))"
    input_sha = hashlib.sha256(source.encode("utf-8")).hexdigest()
    valid = (
        "GHOST_RULER_TOOL_V3"
        f" grammar_sha256={grammar_sha} input_sha256={input_sha}"
        " before=3 prepass=2 after=2 prepass_steps=1 prepass_attempts=3"
        " enodes=7 ematches=11 iterations=2 saturated=true"
        " expr=(mul x (add y z))"
    )
    minimum, counts = verify(valid, source, grammar_sha)
    assert minimum == 2 and counts
    mutations = (
        valid.replace("(mul x (add y z))", "(add x (add y z))"),
        valid.replace("input_sha256=", "input_sha256=" + "0", 1),
        valid.replace("after=2", "after=3"),
        valid + "\nEXTRA",
    )
    rejected = 0
    for mutation in mutations:
        try:
            verify(mutation, source, grammar_sha)
        except VerificationError:
            rejected += 1
    if rejected != len(mutations):
        raise AssertionError("mutation rejection was incomplete")
    control = (
        "GHOST_POLY_CONTROL_V3 method=brute_force before=3 after=2"
        " work=359 unit=semantic_classes prepass_steps=0 saturated=true"
        " expr=(mul x (add y z))"
    )
    method, control_cost = verify_control(control, source)
    assert method == "brute_force" and control_cost == 2
    print(
        "GHOST_POLY_VERIFY_V3_SELFTEST PASS"
        f" mutations_rejected={rejected}_of_{len(mutations)}"
        " exact_semantics=true global_minimum=true independent_imports=true"
    )


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--grammar-sha")
    parser.add_argument("--expression")
    parser.add_argument("--max-cost", type=int, default=4)
    parser.add_argument("--control", action="store_true")
    args = parser.parse_args(argv)
    if args.selftest:
        selftest()
        return
    if not args.grammar_sha or args.expression is None:
        if not args.control or args.expression is None:
            parser.error("--expression and either --grammar-sha or --control are required")
    line = sys.stdin.read()
    if args.control:
        method, cost = verify_control(line, args.expression)
        print(f"GHOST_POLY_VERIFY_CONTROL_V3 PASS method={method} after={cost}")
        return
    minimum, counts = verify(
        line,
        args.expression,
        args.grammar_sha,
        max_cost=args.max_cost,
    )
    print(
        "GHOST_POLY_VERIFY_V3 PASS"
        f" globally_minimal_ops={minimum}"
        f" proof_layer_counts={':'.join(map(str, counts))}"
    )


if __name__ == "__main__":
    main()
