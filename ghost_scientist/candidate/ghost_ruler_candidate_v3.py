#!/usr/bin/env python3
"""Contained Ghost Ruler v3 tool constructor.

The candidate receives one visible algebraic expression and one previously
machine-generated, frozen rule grammar.  It performs an outcome-learned
cost-reducing prepass, then equality saturation with the fixed ring axioms, and
emits exactly one expression tool.

This source has no polynomial oracle, global-optimality search, target
generator, development corpus, control scores, or evaluator implementation.
"""

from __future__ import annotations

import ctypes
import dataclasses
import errno
import hashlib
import pathlib
import sys
from typing import Iterator, Mapping, MutableMapping, Sequence


Expr = str | tuple[str, "Expr", "Expr"]
BINARY_OPS = ("add", "mul", "sub")
COMMUTATIVE = frozenset(("add", "mul"))


class ParseError(ValueError):
    pass


def parse_expr(text: str) -> Expr:
    tokens = text.replace("(", " ( ").replace(")", " ) ").split()
    position = 0

    def parse_one() -> Expr:
        nonlocal position
        if position >= len(tokens):
            raise ParseError("unexpected end")
        token = tokens[position]
        position += 1
        if token != "(":
            if token == ")":
                raise ParseError("unexpected close")
            return token
        if position >= len(tokens):
            raise ParseError("missing operator")
        op = tokens[position]
        position += 1
        if op not in BINARY_OPS:
            raise ParseError("unknown operator")
        left = parse_one()
        right = parse_one()
        if position >= len(tokens) or tokens[position] != ")":
            raise ParseError("missing close")
        position += 1
        return (op, left, right)

    expression = parse_one()
    if position != len(tokens):
        raise ParseError("extra tokens")
    return expression


def format_expr(expr: Expr) -> str:
    if isinstance(expr, str):
        return expr
    return f"({expr[0]} {format_expr(expr[1])} {format_expr(expr[2])})"


def op_cost(expr: Expr) -> int:
    if isinstance(expr, str):
        return 0
    return 1 + op_cost(expr[1]) + op_cost(expr[2])


def canonical_syntax(expr: Expr) -> Expr:
    if isinstance(expr, str):
        return expr
    op, left, right = expr
    left = canonical_syntax(left)
    right = canonical_syntax(right)
    if op in COMMUTATIVE and format_expr(right) < format_expr(left):
        left, right = right, left
    return (op, left, right)


@dataclasses.dataclass(frozen=True)
class Rule:
    lhs: Expr
    rhs: Expr


def load_rules(path: pathlib.Path) -> tuple[list[Rule], bytes]:
    raw = path.read_bytes()
    rules: list[Rule] = []
    for line in raw.decode("utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        lhs, marker, rhs = line.partition("=>")
        if not marker:
            raise ValueError("malformed grammar rule")
        rules.append(Rule(parse_expr(lhs.strip()), parse_expr(rhs.strip())))
    if not rules:
        raise ValueError("empty grammar")
    return rules, raw


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


def greedy_rewrite(expr: Expr, rules: Sequence[Rule], limit: int = 4096) -> tuple[Expr, int, int]:
    current = canonical_syntax(expr)
    steps = 0
    attempts = 0
    while steps < limit:
        changed = False
        for rule in rules:
            attempts += 1
            candidate, applied = rewrite_once(current, rule)
            if not applied:
                continue
            current = candidate
            steps += 1
            changed = True
            break
        if not changed:
            return current, steps, attempts
    raise RuntimeError("prepass budget exhausted")


@dataclasses.dataclass(frozen=True, order=True)
class ENode:
    op: str
    children: tuple[int, ...] = ()


class EGraph:
    def __init__(self, node_limit: int) -> None:
        self.node_limit = node_limit
        self.parent: list[int] = []
        self.rank: list[int] = []
        self.classes: list[set[ENode]] = []
        self.hashcons: dict[ENode, int] = {}
        self.enodes_added = 0
        self.unions = 0
        self.rebuilds = 0
        self.matches = 0

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
        previous = self.hashcons.get(node)
        if previous is not None:
            return self.find(previous)
        if self.enodes_added >= self.node_limit:
            raise RuntimeError("node limit")
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
            hashcons: dict[ENode, int] = {}
            for root in self.roots():
                nodes = {self.canonical_enode(node) for node in self.classes[root]}
                self.classes[root] = nodes
                for node in sorted(nodes):
                    previous = hashcons.get(node)
                    if previous is None:
                        hashcons[node] = root
                    elif self.find(previous) != self.find(root):
                        self.union(previous, root)
                        changed = True
            self.hashcons = {
                self.canonical_enode(node): self.find(class_id)
                for node, class_id in hashcons.items()
            }
            self.rebuilds += 1
            if not changed:
                return

    def match(
        self,
        pattern: Expr,
        class_id: int,
        bindings: Mapping[str, int],
    ) -> Iterator[dict[str, int]]:
        self.matches += 1
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
        for node in tuple(self.classes[class_id]):
            node = self.canonical_enode(node)
            if node.op != pattern[0] or len(node.children) != 2:
                continue
            for left in self.match(pattern[1], node.children[0], bindings):
                yield from self.match(pattern[2], node.children[1], left)

    def instantiate(self, pattern: Expr, bindings: Mapping[str, int]) -> int:
        if isinstance(pattern, str):
            if pattern.startswith("?"):
                return self.find(bindings[pattern])
            return self.add_enode(ENode(pattern))
        left = self.instantiate(pattern[1], bindings)
        right = self.instantiate(pattern[2], bindings)
        return self.add_enode(ENode(pattern[0], (left, right)))

    def apply_rule(self, rule: Rule) -> int:
        applications: list[tuple[int, dict[str, int]]] = []
        for root in self.roots():
            for bindings in self.match(rule.lhs, root, {}):
                applications.append((root, bindings))
        before = self.enodes_added + self.unions
        for root, bindings in applications:
            self.union(root, self.instantiate(rule.rhs, bindings))
        after = self.enodes_added + self.unions
        if after != before:
            self.rebuild()
        return after - before

    def saturate(self, rules: Sequence[Rule], iteration_limit: int) -> tuple[int, bool]:
        self.rebuild()
        for iteration in range(1, iteration_limit + 1):
            changed = 0
            try:
                for rule in rules:
                    changed += self.apply_rule(rule)
            except RuntimeError as exc:
                if str(exc) != "node limit":
                    raise
                self.rebuild()
                return iteration, False
            if changed == 0:
                return iteration, True
        return iteration_limit, False

    def extract(self, class_id: int) -> tuple[Expr, int]:
        infinity = 1 << 60
        roots = self.roots()
        costs = {root: infinity for root in roots}
        best: dict[int, tuple[ENode, tuple[Expr, ...]]] = {}
        changed = True
        while changed:
            changed = False
            for root in roots:
                for node in self.classes[root]:
                    node = self.canonical_enode(node)
                    if not node.children:
                        cost = 0
                        children: tuple[Expr, ...] = ()
                    else:
                        child_roots = tuple(self.find(child) for child in node.children)
                        if any(costs.get(child, infinity) == infinity for child in child_roots):
                            continue
                        cost = 1 + sum(costs[child] for child in child_roots)
                        children = tuple(self.best_expr(child, best) for child in child_roots)
                    expression = self.node_expr(node, children)
                    if cost < costs[root] or (
                        cost == costs[root]
                        and root in best
                        and format_expr(expression)
                        < format_expr(self.node_expr(best[root][0], best[root][1]))
                    ):
                        costs[root] = cost
                        best[root] = (node, children)
                        changed = True
        root = self.find(class_id)
        if root not in best:
            raise RuntimeError("extraction failed")
        return self.node_expr(best[root][0], best[root][1]), costs[root]

    @staticmethod
    def node_expr(node: ENode, children: tuple[Expr, ...]) -> Expr:
        if not node.children:
            return node.op
        return (node.op, children[0], children[1])

    @classmethod
    def best_expr(
        cls,
        root: int,
        best: Mapping[int, tuple[ENode, tuple[Expr, ...]]],
    ) -> Expr:
        node, children = best[root]
        return cls.node_expr(node, children)


def fixed_rules() -> list[Rule]:
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
    forward = [Rule(parse_expr(lhs), parse_expr(rhs)) for lhs, rhs in pairs]
    reverse = [Rule(rule.rhs, rule.lhs) for rule in forward[5:]]
    return forward + reverse


def install_final_allowlist() -> None:
    library = ctypes.CDLL("libseccomp.so.2", use_errno=True)
    library.seccomp_init.argtypes = (ctypes.c_uint32,)
    library.seccomp_init.restype = ctypes.c_void_p
    library.seccomp_release.argtypes = (ctypes.c_void_p,)
    library.seccomp_syscall_resolve_name.argtypes = (ctypes.c_char_p,)
    library.seccomp_syscall_resolve_name.restype = ctypes.c_int
    library.seccomp_rule_add_array.argtypes = (
        ctypes.c_void_p,
        ctypes.c_uint32,
        ctypes.c_int,
        ctypes.c_uint,
        ctypes.c_void_p,
    )
    library.seccomp_load.argtypes = (ctypes.c_void_p,)
    default_errno_eperm = 0x00050001
    allow = 0x7FFF0000
    context = library.seccomp_init(default_errno_eperm)
    if not context:
        raise RuntimeError("seccomp_init failed")
    try:
        allowed = (
            b"read",
            b"write",
            b"close",
            b"fstat",
            b"newfstatat",
            b"lseek",
            b"mmap",
            b"mprotect",
            b"munmap",
            b"brk",
            b"rt_sigaction",
            b"rt_sigprocmask",
            b"rt_sigreturn",
            b"sigaltstack",
            b"ioctl",
            b"arch_prctl",
            b"set_tid_address",
            b"set_robust_list",
            b"rseq",
            b"futex",
            b"madvise",
            b"getrandom",
            b"prlimit64",
            b"exit",
            b"exit_group",
        )
        for name in allowed:
            number = library.seccomp_syscall_resolve_name(name)
            if number < 0:
                raise RuntimeError(f"unknown syscall {name!r}")
            if library.seccomp_rule_add_array(context, allow, number, 0, None) != 0:
                raise RuntimeError(f"seccomp rule failed for {name!r}")
        if library.seccomp_load(context) != 0:
            error_number = ctypes.get_errno()
            raise OSError(error_number, "seccomp_load failed")
    finally:
        library.seccomp_release(context)


def probe_final_allowlist() -> None:
    libc = ctypes.CDLL(None, use_errno=True)
    libc.syscall.restype = ctypes.c_long
    seccomp = ctypes.CDLL("libseccomp.so.2")
    seccomp.seccomp_syscall_resolve_name.argtypes = (ctypes.c_char_p,)
    seccomp.seccomp_syscall_resolve_name.restype = ctypes.c_int
    probes = (
        (b"fork", 0, 0, 0),
        (b"openat", -100, 0, 0),
        (b"socket", 2, 1, 0),
        (b"unshare", 0, 0, 0),
        (b"kill", 1, 0, 0),
        (b"clock_gettime", 1, 0, 0),
    )
    resolved = tuple(
        (name, seccomp.seccomp_syscall_resolve_name(name), a0, a1, a2)
        for name, a0, a1, a2 in probes
    )
    if any(number < 0 for _name, number, _a0, _a1, _a2 in resolved):
        raise RuntimeError("final probe could not resolve a syscall")

    install_final_allowlist()
    results: list[str] = []
    for name, number, a0, a1, a2 in resolved:
        ctypes.set_errno(0)
        result = libc.syscall(number, a0, a1, a2)
        passed = result == -1 and ctypes.get_errno() == errno.EPERM
        results.append(f"{name.decode('ascii')}={'EPERM' if passed else 'NOT_EPERM'}")
        if not passed:
            raise RuntimeError(f"final allow-list did not deny {name!r}")
    print(
        "GHOST_RULER_FINAL_PROBE_V3 PASS"
        " policy=default_deny denials=6 "
        + " ".join(results)
    )


def main() -> None:
    if sys.argv[1:] == ["--probe-final"]:
        probe_final_allowlist()
        return
    if len(sys.argv) != 4:
        raise SystemExit(
            "usage: candidate <grammar> <node_limit> <expression> | --probe-final"
        )
    grammar_path = pathlib.Path(sys.argv[1])
    node_limit = int(sys.argv[2])
    if node_limit != 5000:
        raise ValueError("candidate node limit must be 5000")
    source = parse_expr(sys.argv[3])
    learned_rules, grammar_bytes = load_rules(grammar_path)
    grammar_sha = hashlib.sha256(grammar_bytes).hexdigest()
    input_sha = hashlib.sha256(format_expr(source).encode("utf-8")).hexdigest()

    # No target construction or output occurs before the candidate's final
    # default-deny filter is active.
    install_final_allowlist()

    reduced, prepass_steps, prepass_attempts = greedy_rewrite(source, learned_rules)
    graph = EGraph(node_limit=node_limit)
    root = graph.add_expr(reduced)
    iterations, saturated = graph.saturate(fixed_rules(), 12)
    result, result_cost = graph.extract(root)
    print(
        "GHOST_RULER_TOOL_V3"
        f" grammar_sha256={grammar_sha} input_sha256={input_sha}"
        f" before={op_cost(source)} prepass={op_cost(reduced)} after={result_cost}"
        f" prepass_steps={prepass_steps} prepass_attempts={prepass_attempts}"
        f" enodes={graph.enodes_added} ematches={graph.matches}"
        f" iterations={iterations} saturated={str(saturated).lower()}"
        f" expr={format_expr(result)}"
    )


if __name__ == "__main__":
    main()
