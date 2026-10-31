#!/usr/bin/env python3
"""Ghost Scientist v3: exact rule inference and independent equality saturation.

This file is evaluator/development infrastructure, not candidate code.  It has
two deliberately separate jobs:

* infer universally valid rewrite rules by grouping enumerated expressions by
  exact polynomial normal form; and
* run a conventional e-graph (hash-consed e-nodes, union/find congruence
  closure, e-matching, saturation, and cost extraction) as the strong external
  equality-saturation control.

The term algebra is supplied.  Individual rewrite laws are not.  Rules use
metavariables ?a, ?b, and ?c and are accepted only when exact integer
polynomial normalization proves both sides identical.
"""

from __future__ import annotations

import argparse
import collections
import dataclasses
import hashlib
import json
import pathlib
import random
import secrets
import sys
from typing import Dict, Iterable, Iterator, Mapping, MutableMapping, Sequence


Expr = str | tuple[str, "Expr", "Expr"]
Poly = tuple[tuple[tuple[int, int, int], int], ...]

COMMUTATIVE = frozenset(("add", "mul"))
BINARY_OPS = ("add", "mul", "sub")
META_VARS = ("?a", "?b", "?c")
OBJECT_VARS = ("x", "y", "z")
LEAVES = META_VARS + ("0", "1", "2")


class ParseError(ValueError):
    pass


def tokenize(text: str) -> list[str]:
    return text.replace("(", " ( ").replace(")", " ) ").split()


def parse_expr(text: str) -> Expr:
    tokens = tokenize(text)
    position = 0

    def parse_one() -> Expr:
        nonlocal position
        if position >= len(tokens):
            raise ParseError("unexpected end of expression")
        token = tokens[position]
        position += 1
        if token != "(":
            if token == ")":
                raise ParseError("unexpected closing parenthesis")
            return token
        if position >= len(tokens):
            raise ParseError("missing operator")
        op = tokens[position]
        position += 1
        if op not in BINARY_OPS:
            raise ParseError(f"unknown operator: {op}")
        left = parse_one()
        right = parse_one()
        if position >= len(tokens) or tokens[position] != ")":
            raise ParseError("missing closing parenthesis")
        position += 1
        return (op, left, right)

    expression = parse_one()
    if position != len(tokens):
        raise ParseError("extra tokens after expression")
    return expression


def format_expr(expr: Expr) -> str:
    if isinstance(expr, str):
        return expr
    return f"({expr[0]} {format_expr(expr[1])} {format_expr(expr[2])})"


def op_cost(expr: Expr) -> int:
    if isinstance(expr, str):
        return 0
    return 1 + op_cost(expr[1]) + op_cost(expr[2])


def variables(expr: Expr) -> frozenset[str]:
    if isinstance(expr, str):
        return frozenset((expr,)) if expr.startswith("?") else frozenset()
    return variables(expr[1]) | variables(expr[2])


def canonical_syntax(expr: Expr) -> Expr:
    if isinstance(expr, str):
        return expr
    op, left, right = expr
    left = canonical_syntax(left)
    right = canonical_syntax(right)
    if op in COMMUTATIVE and format_expr(right) < format_expr(left):
        left, right = right, left
    return (op, left, right)


def poly_const(value: int) -> Poly:
    if value == 0:
        return ()
    return ((((0, 0, 0), value)),)


def poly_var(index: int) -> Poly:
    powers = [0, 0, 0]
    powers[index] = 1
    return ((tuple(powers), 1),)


def poly_dict(poly: Poly) -> dict[tuple[int, int, int], int]:
    return dict(poly)


def freeze_poly(
    terms: Mapping[tuple[int, int, int], int],
) -> Poly:
    return tuple(sorted((powers, coefficient) for powers, coefficient in terms.items() if coefficient))


def poly_add(left: Poly, right: Poly, right_scale: int = 1) -> Poly:
    result = poly_dict(left)
    for powers, coefficient in right:
        result[powers] = result.get(powers, 0) + right_scale * coefficient
    return freeze_poly(result)


def poly_mul(left: Poly, right: Poly) -> Poly:
    result: dict[tuple[int, int, int], int] = {}
    for lp, lc in left:
        for rp, rc in right:
            powers = (lp[0] + rp[0], lp[1] + rp[1], lp[2] + rp[2])
            result[powers] = result.get(powers, 0) + lc * rc
    return freeze_poly(result)


def polynomial(expr: Expr) -> Poly:
    if isinstance(expr, str):
        if expr in META_VARS:
            return poly_var(META_VARS.index(expr))
        if expr in OBJECT_VARS:
            return poly_var(OBJECT_VARS.index(expr))
        try:
            return poly_const(int(expr))
        except ValueError as exc:
            raise ValueError(f"non-polynomial leaf: {expr}") from exc
    op, left_expr, right_expr = expr
    left = polynomial(left_expr)
    right = polynomial(right_expr)
    if op == "add":
        return poly_add(left, right)
    if op == "sub":
        return poly_add(left, right, -1)
    if op == "mul":
        return poly_mul(left, right)
    raise ValueError(f"unknown polynomial operator: {op}")


@dataclasses.dataclass(frozen=True, order=True)
class Rule:
    lhs_text: str
    rhs_text: str

    @property
    def lhs(self) -> Expr:
        return parse_expr(self.lhs_text)

    @property
    def rhs(self) -> Expr:
        return parse_expr(self.rhs_text)

    @property
    def gain(self) -> int:
        return op_cost(self.lhs) - op_cost(self.rhs)

    def validate(self) -> None:
        lhs = self.lhs
        rhs = self.rhs
        if polynomial(lhs) != polynomial(rhs):
            raise ValueError(f"unsound rule: {self.lhs_text} => {self.rhs_text}")
        if not variables(rhs) <= variables(lhs):
            raise ValueError(f"rule introduces variables: {self.lhs_text} => {self.rhs_text}")
        if isinstance(lhs, str):
            raise ValueError(f"variable/constant lhs is forbidden: {self.lhs_text}")

    def line(self) -> str:
        return f"{self.lhs_text} => {self.rhs_text}"


def canonicalize_rule_variables(lhs: Expr, rhs: Expr) -> Rule:
    mapping: dict[str, str] = {}

    def rename(expr: Expr) -> Expr:
        if isinstance(expr, str):
            if not expr.startswith("?"):
                return expr
            if expr not in mapping:
                if len(mapping) >= len(META_VARS):
                    raise ValueError("too many rule variables")
                mapping[expr] = META_VARS[len(mapping)]
            return mapping[expr]
        return (expr[0], rename(expr[1]), rename(expr[2]))

    renamed_lhs = rename(lhs)
    renamed_rhs = rename(rhs)
    return Rule(format_expr(renamed_lhs), format_expr(renamed_rhs))


def enumerate_terms(
    max_cost: int,
    variants_per_semantic_class: int = 12,
) -> tuple[list[list[Expr]], dict[Poly, list[Expr]]]:
    """Enumerate terms and retain bounded syntactic variants per exact meaning."""
    by_cost: list[list[Expr]] = [[] for _ in range(max_cost + 1)]
    by_cost[0] = list(LEAVES)
    semantic: dict[Poly, list[Expr]] = collections.defaultdict(list)
    seen_text: set[str] = set()
    for leaf in by_cost[0]:
        semantic[polynomial(leaf)].append(leaf)
        seen_text.add(format_expr(leaf))

    for cost in range(1, max_cost + 1):
        current: list[Expr] = []
        for left_cost in range(cost):
            right_cost = cost - 1 - left_cost
            for left in by_cost[left_cost]:
                for right in by_cost[right_cost]:
                    for op in BINARY_OPS:
                        if op in COMMUTATIVE and format_expr(right) < format_expr(left):
                            continue
                        expr = (op, left, right)
                        text = format_expr(expr)
                        if text in seen_text:
                            continue
                        seen_text.add(text)
                        meaning = polynomial(expr)
                        variants = semantic[meaning]
                        if len(variants) >= variants_per_semantic_class:
                            continue
                        variants.append(expr)
                        current.append(expr)
        by_cost[cost] = current
    return by_cost, semantic


def infer_rules(
    max_cost: int,
    max_rules: int,
    variants_per_semantic_class: int = 12,
) -> tuple[list[Rule], dict[str, int]]:
    by_cost, semantic = enumerate_terms(max_cost, variants_per_semantic_class)
    candidates: dict[str, Rule] = {}
    collision_classes = 0
    for variants in semantic.values():
        if len(variants) < 2:
            continue
        collision_classes += 1
        ordered = sorted(variants, key=lambda expr: (op_cost(expr), format_expr(expr)))
        best = ordered[0]
        for worse in ordered[1:]:
            if op_cost(worse) <= op_cost(best):
                continue
            rule = canonicalize_rule_variables(worse, best)
            try:
                rule.validate()
            except ValueError:
                continue
            previous = candidates.get(rule.lhs_text)
            if previous is None or (
                op_cost(rule.rhs),
                rule.rhs_text,
            ) < (
                op_cost(previous.rhs),
                previous.rhs_text,
            ):
                candidates[rule.lhs_text] = rule
    ranked = sorted(
        candidates.values(),
        key=lambda rule: (
            -len(variables(rule.lhs)),
            -rule.gain,
            op_cost(rule.rhs),
            len(rule.lhs_text),
            rule.lhs_text,
            rule.rhs_text,
        ),
    )
    rules = ranked[:max_rules]
    stats = {
        "max_cost": max_cost,
        "expressions": sum(len(layer) for layer in by_cost),
        "semantic_classes": len(semantic),
        "collision_classes": collision_classes,
        "candidate_rules": len(candidates),
        "emitted_rules": len(rules),
    }
    return rules, stats


def match_tree(pattern: Expr, term: Expr, bindings: MutableMapping[str, Expr]) -> bool:
    if isinstance(pattern, str):
        if pattern.startswith("?"):
            previous = bindings.get(pattern)
            if previous is None:
                bindings[pattern] = term
                return True
            return previous == term
        return pattern == term
    if isinstance(term, str) or pattern[0] != term[0]:
        return False
    snapshot = dict(bindings)
    if match_tree(pattern[1], term[1], bindings) and match_tree(pattern[2], term[2], bindings):
        return True
    bindings.clear()
    bindings.update(snapshot)
    return False


def instantiate(pattern: Expr, bindings: Mapping[str, Expr]) -> Expr:
    if isinstance(pattern, str):
        return bindings.get(pattern, pattern)
    return (pattern[0], instantiate(pattern[1], bindings), instantiate(pattern[2], bindings))


def rewrite_once(expr: Expr, rule: Rule) -> tuple[Expr, bool]:
    bindings: dict[str, Expr] = {}
    if match_tree(rule.lhs, expr, bindings):
        replacement = canonical_syntax(instantiate(rule.rhs, bindings))
        if op_cost(replacement) < op_cost(expr):
            return replacement, True
    if isinstance(expr, str):
        return expr, False
    op, left, right = expr
    new_left, changed = rewrite_once(left, rule)
    if changed:
        return canonical_syntax((op, new_left, right)), True
    new_right, changed = rewrite_once(right, rule)
    if changed:
        return canonical_syntax((op, left, new_right)), True
    return expr, False


def greedy_rewrite(expr: Expr, rules: Sequence[Rule], max_steps: int = 1024) -> tuple[Expr, int]:
    current = canonical_syntax(expr)
    steps = 0
    while steps < max_steps:
        changed = False
        for rule in rules:
            candidate, applied = rewrite_once(current, rule)
            if not applied:
                continue
            if polynomial(candidate) != polynomial(current):
                raise RuntimeError(f"rewrite changed semantics: {rule.line()}")
            current = candidate
            steps += 1
            changed = True
            break
        if not changed:
            return current, steps
    raise RuntimeError("greedy rewrite step budget exhausted")


@dataclasses.dataclass(frozen=True, order=True)
class ENode:
    op: str
    children: tuple[int, ...] = ()


class EGraph:
    """Small conventional e-graph with explicit congruence rebuilding."""

    def __init__(self, node_limit: int = 100_000) -> None:
        self.node_limit = node_limit
        self.parent: list[int] = []
        self.rank: list[int] = []
        self.classes: list[set[ENode]] = []
        self.hashcons: dict[ENode, int] = {}
        self.enodes_added = 0
        self.unions = 0
        self.rebuilds = 0

    def make_class(self) -> int:
        class_id = len(self.parent)
        self.parent.append(class_id)
        self.rank.append(0)
        self.classes.append(set())
        return class_id

    def find(self, class_id: int) -> int:
        root = class_id
        while self.parent[root] != root:
            root = self.parent[root]
        while self.parent[class_id] != class_id:
            parent = self.parent[class_id]
            self.parent[class_id] = root
            class_id = parent
        return root

    def union(self, left: int, right: int) -> int:
        left = self.find(left)
        right = self.find(right)
        if left == right:
            return left
        if self.rank[left] < self.rank[right]:
            left, right = right, left
        self.parent[right] = left
        if self.rank[left] == self.rank[right]:
            self.rank[left] += 1
        self.classes[left].update(self.classes[right])
        self.classes[right].clear()
        self.unions += 1
        return left

    def canonical_enode(self, node: ENode) -> ENode:
        return ENode(node.op, tuple(self.find(child) for child in node.children))

    def add_enode(self, node: ENode) -> int:
        node = self.canonical_enode(node)
        existing = self.hashcons.get(node)
        if existing is not None:
            return self.find(existing)
        if self.enodes_added >= self.node_limit:
            raise RuntimeError("egraph node limit reached")
        class_id = self.make_class()
        self.classes[class_id].add(node)
        self.hashcons[node] = class_id
        self.enodes_added += 1
        return class_id

    def add_expr(self, expr: Expr) -> int:
        if isinstance(expr, str):
            return self.add_enode(ENode(expr))
        left = self.add_expr(expr[1])
        right = self.add_expr(expr[2])
        return self.add_enode(ENode(expr[0], (left, right)))

    def roots(self) -> list[int]:
        return [index for index in range(len(self.parent)) if self.find(index) == index]

    def rebuild(self) -> None:
        while True:
            changed = False
            new_hashcons: dict[ENode, int] = {}
            for root in self.roots():
                canonical_nodes = {self.canonical_enode(node) for node in self.classes[root]}
                self.classes[root] = canonical_nodes
                for node in sorted(canonical_nodes):
                    previous = new_hashcons.get(node)
                    if previous is None:
                        new_hashcons[node] = root
                    elif self.find(previous) != self.find(root):
                        self.union(previous, root)
                        changed = True
            self.hashcons = {
                self.canonical_enode(node): self.find(class_id)
                for node, class_id in new_hashcons.items()
            }
            self.rebuilds += 1
            if not changed:
                return

    def _match(
        self,
        pattern: Expr,
        class_id: int,
        bindings: Mapping[str, int],
    ) -> Iterator[dict[str, int]]:
        class_id = self.find(class_id)
        if isinstance(pattern, str):
            if pattern.startswith("?"):
                previous = bindings.get(pattern)
                if previous is None:
                    result = dict(bindings)
                    result[pattern] = class_id
                    yield result
                elif self.find(previous) == class_id:
                    yield dict(bindings)
                return
            if ENode(pattern) in self.classes[class_id]:
                yield dict(bindings)
            return
        op, left_pattern, right_pattern = pattern
        for node in tuple(self.classes[class_id]):
            node = self.canonical_enode(node)
            if node.op != op or len(node.children) != 2:
                continue
            for left_bindings in self._match(left_pattern, node.children[0], bindings):
                yield from self._match(right_pattern, node.children[1], left_bindings)

    def _instantiate(self, pattern: Expr, bindings: Mapping[str, int]) -> int:
        if isinstance(pattern, str):
            if pattern.startswith("?"):
                return self.find(bindings[pattern])
            return self.add_enode(ENode(pattern))
        left = self._instantiate(pattern[1], bindings)
        right = self._instantiate(pattern[2], bindings)
        return self.add_enode(ENode(pattern[0], (left, right)))

    def apply_rule(self, rule: Rule) -> int:
        applications: list[tuple[int, dict[str, int]]] = []
        for root in self.roots():
            for bindings in self._match(rule.lhs, root, {}):
                applications.append((root, bindings))
        unions_before = self.unions
        nodes_before = self.enodes_added
        for root, bindings in applications:
            rhs = self._instantiate(rule.rhs, bindings)
            self.union(root, rhs)
        if self.unions != unions_before or self.enodes_added != nodes_before:
            self.rebuild()
        return (self.unions - unions_before) + (self.enodes_added - nodes_before)

    def saturate(self, rules: Sequence[Rule], iteration_limit: int = 16) -> int:
        iterations = 0
        self.rebuild()
        for _ in range(iteration_limit):
            iterations += 1
            changed = 0
            for rule in rules:
                changed += self.apply_rule(rule)
            if changed == 0:
                break
        return iterations

    def extract(self, class_id: int) -> tuple[Expr, int]:
        roots = self.roots()
        infinity = 1 << 60
        costs = {root: infinity for root in roots}
        best: dict[int, tuple[ENode, tuple[Expr, ...]]] = {}
        changed = True
        while changed:
            changed = False
            for root in roots:
                root = self.find(root)
                for node in self.classes[root]:
                    node = self.canonical_enode(node)
                    if not node.children:
                        candidate_cost = 0
                        child_exprs: tuple[Expr, ...] = ()
                    else:
                        child_roots = tuple(self.find(child) for child in node.children)
                        if any(costs.get(child, infinity) == infinity for child in child_roots):
                            continue
                        candidate_cost = 1 + sum(costs[child] for child in child_roots)
                        child_exprs = tuple(self._best_expr(child, best) for child in child_roots)
                    if candidate_cost < costs[root]:
                        costs[root] = candidate_cost
                        best[root] = (node, child_exprs)
                        changed = True
                    elif candidate_cost == costs[root] and root in best:
                        candidate = self._node_expr(node, child_exprs)
                        existing = self._node_expr(best[root][0], best[root][1])
                        if format_expr(candidate) < format_expr(existing):
                            best[root] = (node, child_exprs)
                            changed = True
        root = self.find(class_id)
        if root not in best:
            raise RuntimeError("cannot extract an expression from eclass")
        expression = self._node_expr(best[root][0], best[root][1])
        return expression, costs[root]

    @staticmethod
    def _node_expr(node: ENode, children: tuple[Expr, ...]) -> Expr:
        if not node.children:
            return node.op
        return (node.op, children[0], children[1])

    @classmethod
    def _best_expr(
        cls,
        root: int,
        best: Mapping[int, tuple[ENode, tuple[Expr, ...]]],
    ) -> Expr:
        node, children = best[root]
        return cls._node_expr(node, children)

    def stats(self) -> dict[str, int]:
        return {
            "enodes": self.enodes_added,
            "eclasses": len(self.roots()),
            "unions": self.unions,
            "rebuilds": self.rebuilds,
        }


def reverse_rule(rule: Rule) -> Rule:
    result = Rule(rule.rhs_text, rule.lhs_text)
    result.validate()
    return result


def fixed_ring_rules() -> list[Rule]:
    pairs = (
        ("(add ?a 0)", "?a"),
        ("(mul ?a 0)", "0"),
        ("(mul ?a 1)", "?a"),
        ("(sub ?a 0)", "?a"),
        ("(sub ?a ?a)", "0"),
        ("(add ?a ?b)", "(add ?b ?a)"),
        ("(mul ?a ?b)", "(mul ?b ?a)"),
        ("(add (add ?a ?b) ?c)", "(add ?a (add ?b ?c))"),
        ("(mul (mul ?a ?b) ?c)", "(mul ?a (mul ?b ?c))"),
        ("(mul ?a (add ?b ?c))", "(add (mul ?a ?b) (mul ?a ?c))"),
        ("(mul ?a (sub ?b ?c))", "(sub (mul ?a ?b) (mul ?a ?c))"),
        ("(sub (add ?a ?b) ?c)", "(add ?a (sub ?b ?c))"),
    )
    rules = [Rule(lhs, rhs) for lhs, rhs in pairs]
    for rule in rules:
        rule.validate()
    # Equality saturation needs both directions for the nontrivial algebraic
    # equalities; one-way identities remain reductions.
    bidirectional = rules[5:]
    return rules + [reverse_rule(rule) for rule in bidirectional]


def structural_ring_rules() -> list[Rule]:
    rules = fixed_ring_rules()
    # Five reductions, then commutativity/associativity in the forward list.
    selected = rules[:9]
    # Reverse rules start after the twelve forward rules; keep reverses for
    # commutativity/associativity only and omit distributive expansion.
    selected.extend(rules[12:16])
    return selected


def load_rules(path: pathlib.Path) -> list[Rule]:
    rules: list[Rule] = []
    for number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=>" not in line:
            raise ValueError(f"{path}:{number}: missing =>")
        lhs, rhs = (part.strip() for part in line.split("=>", 1))
        rule = Rule(lhs, rhs)
        rule.validate()
        rules.append(rule)
    return rules


def write_rules(path: pathlib.Path, rules: Sequence[Rule], metadata: Mapping[str, object]) -> None:
    lines = [
        "# GHOST_RULER_V3",
        "# " + json.dumps(dict(metadata), sort_keys=True, separators=(",", ":")),
    ]
    lines.extend(rule.line() for rule in rules)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def load_corpus(path: pathlib.Path) -> list[tuple[str, Expr]]:
    rows: list[tuple[str, Expr]] = []
    for number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "\t" not in line:
            raise ValueError(f"{path}:{number}: expected label<TAB>expression")
        label, expression_text = line.split("\t", 1)
        expression = parse_expr(expression_text)
        polynomial(expression)
        rows.append((label, expression))
    if not rows:
        raise ValueError(f"{path}: empty development corpus")
    return rows


def load_targets(path: pathlib.Path) -> list[tuple[str, str, int, Expr]]:
    rows: list[tuple[str, str, int, Expr]] = []
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "opaque_id\tphase\tseed_hex\texpression":
        raise ValueError(f"{path}: invalid target header")
    for number, line in enumerate(lines[1:], 2):
        fields = line.split("\t")
        if len(fields) != 4:
            raise ValueError(f"{path}:{number}: expected four tab-separated fields")
        opaque_id, phase, seed_hex, expression_text = fields
        expression = parse_expr(expression_text)
        polynomial(expression)
        rows.append((opaque_id, phase, int(seed_hex.removeprefix("0x"), 16), expression))
    if not rows:
        raise ValueError(f"{path}: no targets")
    return rows


def select_rules_from_outcomes(
    candidates: Sequence[Rule],
    corpus: Sequence[tuple[str, Expr]],
    max_rules: int,
) -> tuple[list[Rule], list[tuple[str, int, int]], int]:
    """Greedily retain only rules that lower declared development tool cost."""
    selected: list[Rule] = []
    current = [(label, canonical_syntax(expression)) for label, expression in corpus]
    total_gain = 0
    remaining = list(candidates)
    while remaining and len(selected) < max_rules:
        best_index: int | None = None
        best_gain = 0
        best_outputs: list[tuple[str, Expr]] = []
        best_key: tuple[object, ...] | None = None
        for index, rule in enumerate(remaining):
            outputs: list[tuple[str, Expr]] = []
            gain = 0
            for label, expression in current:
                rewritten, _steps = greedy_rewrite(expression, (rule,), max_steps=64)
                gain += op_cost(expression) - op_cost(rewritten)
                outputs.append((label, rewritten))
            key = (
                gain,
                len(variables(rule.lhs)),
                rule.gain,
                -op_cost(rule.rhs),
                rule.lhs_text,
                rule.rhs_text,
            )
            if gain > 0 and (best_key is None or key > best_key):
                best_index = index
                best_gain = gain
                best_outputs = outputs
                best_key = key
        if best_index is None:
            break
        selected.append(remaining.pop(best_index))
        current = best_outputs
        total_gain += best_gain
    outcomes = [
        (label, op_cost(original), op_cost(final))
        for (label, original), (_final_label, final) in zip(corpus, current, strict=True)
    ]
    return selected, outcomes, total_gain


def select_rules_independently(
    candidates: Sequence[Rule],
    corpus: Sequence[tuple[str, Expr]],
    max_rules: int,
) -> tuple[list[Rule], list[tuple[str, int, int]], int]:
    """Rank every rule by independent development reductions, then compose."""
    ranked: list[tuple[tuple[object, ...], Rule]] = []
    for rule in candidates:
        gain = 0
        support = 0
        for _label, expression in corpus:
            rewritten, _steps = greedy_rewrite(expression, (rule,), max_steps=64)
            reduction = op_cost(expression) - op_cost(rewritten)
            gain += reduction
            support += int(reduction > 0)
        if gain <= 0:
            continue
        key = (
            gain,
            support,
            len(variables(rule.lhs)),
            rule.gain,
            -op_cost(rule.rhs),
            rule.lhs_text,
            rule.rhs_text,
        )
        ranked.append((key, rule))
    ranked.sort(reverse=True)
    selected = [rule for _key, rule in ranked[:max_rules]]
    outcomes: list[tuple[str, int, int]] = []
    total_gain = 0
    for label, expression in corpus:
        rewritten, _steps = greedy_rewrite(expression, selected, max_steps=1024)
        before = op_cost(expression)
        after = op_cost(rewritten)
        outcomes.append((label, before, after))
        total_gain += before - after
    return selected, outcomes, total_gain


def exact_min_cost(
    target: Poly,
    max_cost: int,
    leaves: Sequence[str] = ("?a", "?b", "?c", "0", "1", "2"),
) -> tuple[int | None, Expr | None, list[int]]:
    """Exhaustive dynamic programming over semantic classes.

    If the target first appears at cost k, no expression with fewer than k
    operators in the declared grammar denotes it.
    """
    layers: list[dict[Poly, Expr]] = [dict() for _ in range(max_cost + 1)]
    for leaf in leaves:
        layers[0].setdefault(polynomial(leaf), leaf)
    counts = [len(layers[0])]
    if target in layers[0]:
        return 0, layers[0][target], counts
    globally_seen = set(layers[0])
    for cost in range(1, max_cost + 1):
        layer = layers[cost]
        for left_cost in range(cost):
            right_cost = cost - 1 - left_cost
            for left_poly, left_expr in layers[left_cost].items():
                for right_poly, right_expr in layers[right_cost].items():
                    combinations = (
                        ("add", poly_add(left_poly, right_poly)),
                        ("mul", poly_mul(left_poly, right_poly)),
                        ("sub", poly_add(left_poly, right_poly, -1)),
                    )
                    for op, meaning in combinations:
                        if meaning in globally_seen or meaning in layer:
                            continue
                        expression: Expr = (op, left_expr, right_expr)
                        layer[meaning] = expression
        counts.append(len(layer))
        if target in layer:
            return cost, layer[target], counts
        globally_seen.update(layer)
    return None, None, counts


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def expression_paths(expr: Expr, prefix: tuple[int, ...] = ()) -> list[tuple[int, ...]]:
    paths = [prefix]
    if not isinstance(expr, str):
        paths.extend(expression_paths(expr[1], prefix + (1,)))
        paths.extend(expression_paths(expr[2], prefix + (2,)))
    return paths


def subtree(expr: Expr, path: Sequence[int]) -> Expr:
    current = expr
    for direction in path:
        if isinstance(current, str):
            raise ValueError("path descends through a leaf")
        current = current[direction]
    return current


def replace_subtree(expr: Expr, path: Sequence[int], replacement: Expr) -> Expr:
    if not path:
        return replacement
    if isinstance(expr, str):
        raise ValueError("path descends through a leaf")
    direction = path[0]
    if direction == 1:
        return (expr[0], replace_subtree(expr[1], path[1:], replacement), expr[2])
    if direction == 2:
        return (expr[0], expr[1], replace_subtree(expr[2], path[1:], replacement))
    raise ValueError("invalid expression path")


def one_standard_expansion(expr: Expr, rng: random.Random) -> Expr:
    path = rng.choice(expression_paths(expr))
    selected = subtree(expr, path)
    atom: Expr = rng.choice(OBJECT_VARS)
    operations: list[Expr] = [
        ("add", selected, "0"),
        ("mul", selected, "1"),
        ("sub", selected, "0"),
        ("sub", ("add", selected, atom), atom),
        ("add", ("sub", selected, atom), atom),
    ]
    if not isinstance(selected, str):
        op, left, right = selected
        if op == "mul" and not isinstance(right, str) and right[0] in ("add", "sub"):
            operations.append(
                (
                    right[0],
                    ("mul", left, right[1]),
                    ("mul", left, right[2]),
                )
            )
        if op == "mul" and not isinstance(left, str) and left[0] in ("add", "sub"):
            operations.append(
                (
                    left[0],
                    ("mul", left[1], right),
                    ("mul", left[2], right),
                )
            )
    replacement = rng.choice(operations)
    expanded = replace_subtree(expr, path, replacement)
    if polynomial(expanded) != polynomial(expr):
        raise RuntimeError("target generator produced an invalid algebraic expansion")
    return expanded


def prospective_compact_bases() -> tuple[tuple[str, Expr], ...]:
    return (
        ("shared_projection_sum", parse_expr("(mul x (add y z))")),
        ("shared_projection_difference", parse_expr("(mul x (sub y z))")),
        ("activation_residual", parse_expr("(add (mul x y) z)")),
        ("two_weight_residual", parse_expr("(sub (mul x y) z)")),
        ("bilinear_sum", parse_expr("(add (mul x y) (mul y z))")),
        ("quadratic_residual", parse_expr("(add (mul x x) y)")),
        ("identity_path", parse_expr("x")),
        ("gated_path", parse_expr("(mul (add x y) z)")),
    )


def generate_targets(count: int, seed: int) -> list[tuple[str, str, int, Expr]]:
    rng = random.Random(seed)
    bases = prospective_compact_bases()
    targets: list[tuple[str, str, int, Expr]] = []
    seen: set[str] = set()
    attempts = 0
    while len(targets) < count:
        attempts += 1
        if attempts > count * 1000:
            raise RuntimeError("could not generate enough unique targets")
        family, compact = rng.choice(bases)
        expanded = compact
        expansion_count = rng.randint(4, 8)
        for _ in range(expansion_count):
            expanded = one_standard_expansion(expanded, rng)
        text = format_expr(expanded)
        if text in seen or op_cost(expanded) <= op_cost(compact):
            continue
        seen.add(text)
        item_seed = rng.getrandbits(64)
        targets.append((f"artifact_{len(targets):03d}", family, item_seed, expanded))
    return targets


def command_infer(args: argparse.Namespace) -> None:
    rules, stats = infer_rules(args.max_cost, args.max_rules, args.variants)
    metadata = {
        **stats,
        "semantics": "exact_integer_polynomial_v1",
        "selection": "compression_then_lexical",
    }
    write_rules(pathlib.Path(args.output), rules, metadata)
    print("GHOST_RULER_INFER_V3 PASS " + " ".join(f"{key}={value}" for key, value in stats.items()))


def command_validate(args: argparse.Namespace) -> None:
    rules = load_rules(pathlib.Path(args.rules))
    for rule in rules:
        rule.validate()
    digest = hashlib.sha256(pathlib.Path(args.rules).read_bytes()).hexdigest()
    print(f"GHOST_RULER_VALIDATE_V3 PASS rules={len(rules)} sha256={digest}")


def command_select(args: argparse.Namespace) -> None:
    pool_path = pathlib.Path(args.pool)
    corpus_path = pathlib.Path(args.corpus)
    candidates = load_rules(pool_path)
    corpus = load_corpus(corpus_path)
    if args.strategy == "greedy":
        selected, outcomes, gain = select_rules_from_outcomes(candidates, corpus, args.max_rules)
    else:
        selected, outcomes, gain = select_rules_independently(candidates, corpus, args.max_rules)
    if not selected or gain <= 0:
        raise RuntimeError("development outcomes selected no cost-reducing rule")
    metadata = {
        "candidate_rules": len(candidates),
        "corpus_rows": len(corpus),
        "corpus_sha256": hashlib.sha256(corpus_path.read_bytes()).hexdigest(),
        "pool_sha256": hashlib.sha256(pool_path.read_bytes()).hexdigest(),
        "selected_rules": len(selected),
        "development_operator_saving": gain,
        "selection": f"{args.strategy}_development_outcome_cost_reduction_v1",
    }
    write_rules(pathlib.Path(args.output), selected, metadata)
    if args.ledger:
        ledger_lines = ["label\tbefore_ops\tafter_ops\tsaving"]
        ledger_lines.extend(
            f"{label}\t{before}\t{after}\t{before - after}"
            for label, before, after in outcomes
        )
        pathlib.Path(args.ledger).write_text("\n".join(ledger_lines) + "\n", encoding="utf-8")
    print(
        "GHOST_RULER_SELECT_V3 PASS"
        f" candidates={len(candidates)} corpus={len(corpus)}"
        f" selected={len(selected)} development_operator_saving={gain}"
    )


def command_select_static(args: argparse.Namespace) -> None:
    pool_path = pathlib.Path(args.pool)
    pool = load_rules(pool_path)
    if args.max_rules <= 0 or args.max_rules > len(pool):
        raise ValueError("invalid static rule count")
    if args.strategy == "ranked":
        selected = pool[: args.max_rules]
        seed_text = "none"
    else:
        if args.seed_hex is None:
            raise ValueError("random static selection requires --seed-hex")
        seed = int(args.seed_hex.removeprefix("0x"), 16)
        indices = list(range(len(pool)))
        random.Random(seed).shuffle(indices)
        selected = [pool[index] for index in indices[: args.max_rules]]
        seed_text = f"0x{seed:032x}"
    metadata = {
        "pool_sha256": hashlib.sha256(pool_path.read_bytes()).hexdigest(),
        "selected_rules": len(selected),
        "selection": f"{args.strategy}_without_development_outcomes_v1",
        "seed_hex": seed_text,
    }
    output = pathlib.Path(args.output)
    write_rules(output, selected, metadata)
    print(
        "GHOST_RULER_SELECT_STATIC_V3 PASS"
        f" strategy={args.strategy} selected={len(selected)}"
        f" sha256={hashlib.sha256(output.read_bytes()).hexdigest()}"
    )


def command_generate(args: argparse.Namespace) -> None:
    if args.seed_hex:
        seed = int(args.seed_hex.removeprefix("0x"), 16)
    else:
        seed = int.from_bytes(secrets.token_bytes(16), "big")
    targets = generate_targets(args.count, seed)
    lines = ["opaque_id\tphase\tseed_hex\texpression"]
    lines.extend(
        f"{opaque_id}\tHELDOUT\t0x{item_seed:016x}\t{format_expr(expression)}"
        for opaque_id, _family, item_seed, expression in targets
    )
    output = pathlib.Path(args.output)
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    audit_path = pathlib.Path(args.audit) if args.audit else None
    if audit_path is not None:
        audit_lines = ["opaque_id\tprivate_family\tinput_ops\tpolynomial_sha256"]
        audit_lines.extend(
            f"{opaque_id}\t{family}\t{op_cost(expression)}"
            f"\t{sha256_text(repr(polynomial(expression)))}"
            for opaque_id, family, _item_seed, expression in targets
        )
        audit_path.write_text("\n".join(audit_lines) + "\n", encoding="utf-8")
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    print(
        "GHOST_RULER_GENERATE_V3 PASS"
        f" count={len(targets)} seed_hex=0x{seed:032x} targets_sha256={digest}"
    )


def command_generate_development(args: argparse.Namespace) -> None:
    seed = int(args.seed_hex.removeprefix("0x"), 16)
    targets = generate_targets(args.count, seed)
    lines = [
        f"{opaque_id}\t{format_expr(expression)}"
        for opaque_id, _family, _item_seed, expression in targets
    ]
    output = pathlib.Path(args.output)
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    print(
        "GHOST_RULER_GENERATE_DEVELOPMENT_V3 PASS"
        f" count={len(targets)} seed_hex=0x{seed:032x} corpus_sha256={digest}"
    )


def command_compare(args: argparse.Namespace) -> None:
    targets = load_targets(pathlib.Path(args.targets))
    learned_rules = load_rules(pathlib.Path(args.rules))
    rows = [
        "opaque_id\tinput_ops\tlearned_ops\tfixed_egraph_ops\tlearned_egraph_ops"
        "\tglobal_min_ops\tlearned_steps\tfixed_enodes\tlearned_enodes"
        "\tfixed_iterations\tlearned_iterations\tlearned_globally_minimal"
    ]
    learned_sum = 0
    learned_egraph_sum = 0
    fixed_sum = 0
    global_sum = 0
    global_passes = 0
    learned_egraph_global_passes = 0
    strict_wins = 0
    egraph_wins = 0
    egraph_ties = 0
    egraph_losses = 0
    for opaque_id, phase, _seed, expression in targets:
        if phase != "HELDOUT":
            raise ValueError(f"{opaque_id}: target is not HELDOUT")
        learned, learned_steps = greedy_rewrite(expression, learned_rules)

        fixed_graph = EGraph(node_limit=args.fixed_node_limit)
        fixed_root = fixed_graph.add_expr(expression)
        try:
            fixed_iterations = fixed_graph.saturate(fixed_ring_rules(), args.iterations)
        except RuntimeError as exc:
            if str(exc) != "egraph node limit reached":
                raise
            fixed_graph.rebuild()
            fixed_iterations = -1
        fixed, fixed_cost = fixed_graph.extract(fixed_root)

        learned_graph = EGraph(node_limit=args.learned_node_limit)
        if args.learned_fixed_mode == "prepass_full":
            learned_root = learned_graph.add_expr(learned)
            learned_schedule = fixed_ring_rules()
        elif args.learned_fixed_mode == "full":
            learned_root = learned_graph.add_expr(expression)
            learned_schedule = list(learned_rules) + fixed_ring_rules()
        elif args.learned_fixed_mode == "structural":
            learned_root = learned_graph.add_expr(expression)
            learned_schedule = list(learned_rules) + structural_ring_rules()
        elif args.learned_fixed_mode == "reductions":
            learned_root = learned_graph.add_expr(expression)
            learned_schedule = list(learned_rules) + fixed_ring_rules()[:5]
        else:
            learned_root = learned_graph.add_expr(expression)
            learned_schedule = list(learned_rules)
        try:
            learned_iterations = learned_graph.saturate(
                learned_schedule,
                args.iterations,
            )
        except RuntimeError as exc:
            if str(exc) != "egraph node limit reached":
                raise
            learned_graph.rebuild()
            learned_iterations = -1
        learned_egraph, learned_egraph_cost = learned_graph.extract(learned_root)

        meaning = polynomial(expression)
        minimum, _witness, _counts = exact_min_cost(
            meaning,
            args.max_proof_cost,
            leaves=OBJECT_VARS + ("0", "1", "2"),
        )
        if minimum is None:
            raise RuntimeError(f"{opaque_id}: exact minimum was not found")
        for candidate in (learned, fixed, learned_egraph):
            if polynomial(candidate) != meaning:
                raise RuntimeError(f"{opaque_id}: an optimizer changed semantics")
        learned_cost = op_cost(learned)
        learned_sum += learned_cost
        learned_egraph_sum += learned_egraph_cost
        fixed_sum += fixed_cost
        global_sum += minimum
        if learned_cost == minimum:
            global_passes += 1
        if learned_egraph_cost == minimum:
            learned_egraph_global_passes += 1
        if learned_cost < fixed_cost:
            strict_wins += 1
        if learned_egraph_cost < fixed_cost:
            egraph_wins += 1
        elif learned_egraph_cost == fixed_cost:
            egraph_ties += 1
        else:
            egraph_losses += 1
        rows.append(
            f"{opaque_id}\t{op_cost(expression)}\t{learned_cost}\t{fixed_cost}"
            f"\t{learned_egraph_cost}\t{minimum}\t{learned_steps}"
            f"\t{fixed_graph.enodes_added}\t{learned_graph.enodes_added}"
            f"\t{fixed_iterations}\t{learned_iterations}\t{str(learned_cost == minimum).lower()}"
        )
    if args.output:
        pathlib.Path(args.output).write_text("\n".join(rows) + "\n", encoding="utf-8")
    else:
        print("\n".join(rows))
    print(
        "GHOST_RULER_COMPARE_V3"
        f" targets={len(targets)} greedy_learned_sum={learned_sum}"
        f" learned_egraph_sum={learned_egraph_sum} fixed_egraph_sum={fixed_sum}"
        f" global_sum={global_sum} greedy_global_minimal={global_passes}"
        f" learned_egraph_global_minimal={learned_egraph_global_passes}"
        f" greedy_strict_wins_vs_fixed={strict_wins}"
        f" learned_egraph_wins_ties_losses={egraph_wins}_{egraph_ties}_{egraph_losses}"
    )


def command_rewrite(args: argparse.Namespace) -> None:
    expression = parse_expr(args.expression)
    rules = load_rules(pathlib.Path(args.rules))
    result, steps = greedy_rewrite(expression, rules)
    if polynomial(result) != polynomial(expression):
        raise RuntimeError("output is not polynomial-equivalent")
    print(
        "GHOST_RULER_REWRITE_V3 PASS"
        f" before={op_cost(expression)} after={op_cost(result)} steps={steps}"
        f" expr={format_expr(result)}"
    )


def command_egraph(args: argparse.Namespace) -> None:
    expression = parse_expr(args.expression)
    rules = fixed_ring_rules()
    if args.rules:
        rules.extend(load_rules(pathlib.Path(args.rules)))
    graph = EGraph(node_limit=args.node_limit)
    root = graph.add_expr(expression)
    iterations = graph.saturate(rules, args.iterations)
    result, cost = graph.extract(root)
    if polynomial(result) != polynomial(expression):
        raise RuntimeError("egraph extraction is not polynomial-equivalent")
    stats = graph.stats()
    print(
        "GHOST_EGRAPH_V3 PASS"
        f" before={op_cost(expression)} after={cost} iterations={iterations}"
        + "".join(f" {key}={value}" for key, value in stats.items())
        + f" expr={format_expr(result)}"
    )


def run_egraph_control(
    expression: Expr,
    node_limit: int,
    iterations: int,
) -> tuple[Expr, int, EGraph, int, bool]:
    graph = EGraph(node_limit=node_limit)
    root = graph.add_expr(expression)
    try:
        completed_iterations = graph.saturate(fixed_ring_rules(), iterations)
        saturated = True
    except RuntimeError as exc:
        if str(exc) != "egraph node limit reached":
            raise
        graph.rebuild()
        completed_iterations = iterations
        saturated = False
    output, cost = graph.extract(root)
    return output, cost, graph, completed_iterations, saturated


def command_control(args: argparse.Namespace) -> None:
    expression = parse_expr(args.expression)
    before = op_cost(expression)
    prepass_steps = 0
    if args.method == "fixed_simplification":
        output, prepass_steps = greedy_rewrite(expression, fixed_ring_rules()[:5])
        after = op_cost(output)
        work = prepass_steps
        unit = "rewrites"
        saturated = True
    elif args.method == "replay":
        output = canonical_syntax(expression)
        after = op_cost(output)
        work = 0
        unit = "memorized_exact_input_hits"
        saturated = True
    elif args.method == "brute_force":
        minimum, witness, counts = exact_min_cost(
            polynomial(expression),
            args.max_proof_cost,
            leaves=OBJECT_VARS + ("0", "1", "2"),
        )
        if minimum is None or witness is None:
            raise RuntimeError("brute-force control did not reach the target meaning")
        output = witness
        after = minimum
        work = sum(counts)
        unit = "semantic_classes"
        saturated = True
    else:
        source = expression
        if args.method in ("random", "no_probe"):
            if not args.rules:
                raise ValueError(f"{args.method} requires --rules")
            source, prepass_steps = greedy_rewrite(
                expression,
                load_rules(pathlib.Path(args.rules)),
            )
        output, after, graph, _completed_iterations, saturated = run_egraph_control(
            source,
            args.node_limit,
            args.iterations,
        )
        work = graph.enodes_added
        unit = "enodes"
    if polynomial(output) != polynomial(expression):
        raise RuntimeError("control changed exact polynomial semantics")
    print(
        "GHOST_POLY_CONTROL_V3"
        f" method={args.method} before={before} after={after}"
        f" work={work} unit={unit} prepass_steps={prepass_steps}"
        f" saturated={str(saturated).lower()} expr={format_expr(output)}"
    )


def command_prove(args: argparse.Namespace) -> None:
    expression = parse_expr(args.expression)
    target = polynomial(expression)
    cost, witness, counts = exact_min_cost(target, args.max_cost)
    if cost is None or witness is None:
        print(
            "GHOST_POLY_MINIMALITY_V3 NOT_FOUND"
            f" max_cost={args.max_cost} layer_counts={':'.join(map(str, counts))}"
        )
        raise SystemExit(1)
    print(
        "GHOST_POLY_MINIMALITY_V3 PROVEN"
        f" minimal_cost={cost} layer_counts={':'.join(map(str, counts))}"
        f" witness={format_expr(witness)}"
    )


def selftest() -> None:
    samples = (
        "(add (mul ?a ?b) (mul ?a ?c))",
        "(mul ?a (add ?b ?c))",
        "(sub (add ?a ?b) ?b)",
        "(add (mul 2 ?a) (mul ?a ?a))",
    )
    for text in samples:
        assert parse_expr(format_expr(parse_expr(text))) == parse_expr(text)

    factor = Rule("(add (mul ?a ?b) (mul ?a ?c))", "(mul ?a (add ?b ?c))")
    factor.validate()
    rewritten, steps = greedy_rewrite(parse_expr(factor.lhs_text), [factor])
    assert steps == 1 and format_expr(rewritten) == "(mul (add ?b ?c) ?a)"
    assert polynomial(rewritten) == polynomial(factor.lhs)

    graph = EGraph(node_limit=20_000)
    source = parse_expr("(add (mul ?a ?b) (mul ?a ?c))")
    root = graph.add_expr(source)
    iterations = graph.saturate(fixed_ring_rules(), 8)
    extracted, extracted_cost = graph.extract(root)
    assert polynomial(extracted) == polynomial(source)
    assert extracted_cost == 2
    assert iterations >= 1
    assert graph.unions > 0 and graph.rebuilds > 0

    rules, stats = infer_rules(max_cost=3, max_rules=256, variants_per_semantic_class=16)
    assert stats["collision_classes"] > 0
    assert any(rule.gain > 0 for rule in rules)
    assert any(
        polynomial(rule.lhs) == polynomial(factor.lhs) and rule.gain > 0
        for rule in rules
    )
    for rule in rules:
        rule.validate()

    minimal_cost, witness, counts = exact_min_cost(polynomial(parse_expr("(mul ?a ?b)")), 2)
    assert minimal_cost == 1 and witness is not None and counts

    unsound = Rule("(add ?a 1)", "?a")
    try:
        unsound.validate()
    except ValueError:
        pass
    else:
        raise AssertionError("unsound rule was accepted")

    print(
        "GHOST_RULER_V3_SELFTEST PASS"
        f" inferred_rules={len(rules)} egraph_enodes={graph.enodes_added}"
        f" egraph_unions={graph.unions} exact_semantics=true unsound_rejected=true"
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    infer = subparsers.add_parser("infer")
    infer.add_argument("output")
    infer.add_argument("--max-cost", type=int, default=3)
    infer.add_argument("--max-rules", type=int, default=256)
    infer.add_argument("--variants", type=int, default=16)
    infer.set_defaults(function=command_infer)

    validate = subparsers.add_parser("validate")
    validate.add_argument("rules")
    validate.set_defaults(function=command_validate)

    select = subparsers.add_parser("select")
    select.add_argument("pool")
    select.add_argument("corpus")
    select.add_argument("output")
    select.add_argument("--ledger")
    select.add_argument("--max-rules", type=int, default=32)
    select.add_argument("--strategy", choices=("greedy", "independent"), default="greedy")
    select.set_defaults(function=command_select)

    select_static = subparsers.add_parser("select-static")
    select_static.add_argument("pool")
    select_static.add_argument("output")
    select_static.add_argument("--max-rules", type=int, default=128)
    select_static.add_argument("--strategy", choices=("ranked", "random"), required=True)
    select_static.add_argument("--seed-hex")
    select_static.set_defaults(function=command_select_static)

    generate = subparsers.add_parser("generate")
    generate.add_argument("output")
    generate.add_argument("--audit")
    generate.add_argument("--count", type=int, default=60)
    generate.add_argument("--seed-hex")
    generate.set_defaults(function=command_generate)

    generate_development = subparsers.add_parser("generate-development")
    generate_development.add_argument("output")
    generate_development.add_argument("--count", type=int, default=120)
    generate_development.add_argument("--seed-hex", required=True)
    generate_development.set_defaults(function=command_generate_development)

    compare = subparsers.add_parser("compare")
    compare.add_argument("targets")
    compare.add_argument("rules")
    compare.add_argument("--output")
    compare.add_argument("--fixed-node-limit", type=int, default=200_000)
    compare.add_argument("--learned-node-limit", type=int, default=100_000)
    compare.add_argument("--iterations", type=int, default=16)
    compare.add_argument("--max-proof-cost", type=int, default=4)
    compare.add_argument(
        "--learned-fixed-mode",
        choices=("prepass_full", "full", "structural", "reductions", "none"),
        default="full",
    )
    compare.set_defaults(function=command_compare)

    rewrite = subparsers.add_parser("rewrite")
    rewrite.add_argument("rules")
    rewrite.add_argument("expression")
    rewrite.set_defaults(function=command_rewrite)

    egraph = subparsers.add_parser("egraph")
    egraph.add_argument("expression")
    egraph.add_argument("--rules")
    egraph.add_argument("--node-limit", type=int, default=100_000)
    egraph.add_argument("--iterations", type=int, default=16)
    egraph.set_defaults(function=command_egraph)

    control = subparsers.add_parser("control")
    control.add_argument(
        "method",
        choices=(
            "fixed_simplification",
            "equality_saturation",
            "strong_fixed",
            "brute_force",
            "random",
            "replay",
            "no_memory",
            "no_probe",
        ),
    )
    control.add_argument("expression")
    control.add_argument("--rules")
    control.add_argument("--node-limit", type=int, default=5000)
    control.add_argument("--iterations", type=int, default=12)
    control.add_argument("--max-proof-cost", type=int, default=4)
    control.set_defaults(function=command_control)

    prove = subparsers.add_parser("prove")
    prove.add_argument("expression")
    prove.add_argument("--max-cost", type=int, default=5)
    prove.set_defaults(function=command_prove)

    test = subparsers.add_parser("selftest")
    test.set_defaults(function=lambda _args: selftest())
    return parser


def main(argv: Sequence[str] | None = None) -> None:
    parser = build_parser()
    args = parser.parse_args(argv)
    args.function(args)


if __name__ == "__main__":
    main()
