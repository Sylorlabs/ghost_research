#!/usr/bin/env python3
"""Independent, fail-closed expander for Stitch S-expression rewrites.

This module intentionally does not import the graph encoders or the Stitch
control wrapper.  It checks the structural relation that Stitch reports:
an invocation ``(fn_N arg0 ... argK)`` denotes the abstraction body after
simultaneously replacing ``#0 ... #K`` with the corresponding argument AST.
For an open sequence body ``(seq item)``, Stitch may emit one additional
continuation argument; expansion splices it to produce ``(seq item rest)``.

The Foundry encoder writes nullary applications such as ``(dict )``, while
Stitch's parser represents and emits those singleton applications as the leaf
``dict``.  ``canonicalize_stitch`` independently applies that documented
normalization.  Reconstruction equality is therefore byte equality between
*normalized canonical forms*, not between Stitch output and the raw encoder
bytes.
"""

from __future__ import annotations

from dataclasses import dataclass
import re
from typing import Iterable, Mapping, Sequence, TypeAlias


Atom: TypeAlias = str
Node: TypeAlias = Atom | tuple["Node", ...]

_VARIABLE = re.compile(r"#([0-9]+)\Z")
_DEFAULT_MAX_EXPANSIONS = 1_000_000
_DEFAULT_MAX_DEPTH = 20_000


class StitchExpansionError(ValueError):
    """Raised when an S-expression or abstraction relation is invalid."""


@dataclass(frozen=True)
class Abstraction:
    """Validated abstraction definition."""

    name: str
    arity: int
    body: Node

    @property
    def has_open_sequence_continuation(self) -> bool:
        return (
            isinstance(self.body, tuple)
            and len(self.body) == 2
            and self.body[0] == "seq"
        )


@dataclass(frozen=True)
class ExpansionResult:
    """Canonical expansion and exact invocation counts."""

    expanded: str
    counts: Mapping[str, int]

    @property
    def total_expansions(self) -> int:
        return sum(self.counts.values())


def _tokens(source: str) -> Iterable[str]:
    """Tokenize the atom/parenthesis subset used by Stitch."""

    if not isinstance(source, str):
        raise StitchExpansionError("S-expression must be a string")
    index = 0
    length = len(source)
    while index < length:
        char = source[index]
        if char.isspace():
            index += 1
            continue
        if char in "()":
            yield char
            index += 1
            continue
        end = index
        while (
            end < length
            and not source[end].isspace()
            and source[end] not in "()"
        ):
            end += 1
        yield source[index:end]
        index = end


def parse_sexpr(source: str, *, max_depth: int = _DEFAULT_MAX_DEPTH) -> Node:
    """Parse exactly one S-expression without interpreting its atoms."""

    if type(max_depth) is not int or max_depth < 1:
        raise StitchExpansionError("max_depth must be a positive integer")
    tokens = list(_tokens(source))
    if not tokens:
        raise StitchExpansionError("empty S-expression")
    cursor = 0

    def parse_one(depth: int) -> Node:
        nonlocal cursor
        if depth > max_depth:
            raise StitchExpansionError("S-expression nesting limit exceeded")
        if cursor >= len(tokens):
            raise StitchExpansionError("unexpected end of S-expression")
        token = tokens[cursor]
        cursor += 1
        if token == ")":
            raise StitchExpansionError("unexpected closing parenthesis")
        if token != "(":
            return token
        children: list[Node] = []
        while True:
            if cursor >= len(tokens):
                raise StitchExpansionError("unclosed parenthesis")
            if tokens[cursor] == ")":
                cursor += 1
                return tuple(children)
            children.append(parse_one(depth + 1))

    parsed = parse_one(1)
    if cursor != len(tokens):
        raise StitchExpansionError("trailing tokens after S-expression")
    return parsed


def format_sexpr(node: Node) -> str:
    """Serialize an AST in canonical single-space S-expression form."""

    if isinstance(node, str):
        if not node or any(
            char.isspace() or char in "()" for char in node
        ):
            raise StitchExpansionError(f"invalid atom: {node!r}")
        return node
    if not isinstance(node, tuple):
        raise StitchExpansionError(
            f"invalid AST node type: {type(node).__name__}"
        )
    return "(" + " ".join(format_sexpr(child) for child in node) + ")"


def _normalize_singleton_applications(node: Node) -> Node:
    """Apply Stitch's ``(leaf) -> leaf`` parser normalization recursively."""

    if isinstance(node, str):
        return node
    normalized = tuple(
        _normalize_singleton_applications(child) for child in node
    )
    if len(normalized) == 1:
        return normalized[0]
    return normalized


def canonicalize_stitch(source: str) -> str:
    """Return the independent canonical form used for Stitch comparison."""

    return format_sexpr(_normalize_singleton_applications(parse_sexpr(source)))


def _walk_variables(node: Node) -> Iterable[int]:
    if isinstance(node, str):
        match = _VARIABLE.fullmatch(node)
        if match:
            yield int(match.group(1))
        return
    for child in node:
        yield from _walk_variables(child)


def load_abstractions(
    rows: Sequence[Mapping[str, object]],
) -> dict[str, Abstraction]:
    """Validate JSON-shaped Stitch abstraction rows."""

    if isinstance(rows, (str, bytes)) or not isinstance(rows, Sequence):
        raise StitchExpansionError("abstractions must be a sequence")
    definitions: dict[str, Abstraction] = {}
    for position, row in enumerate(rows):
        if not isinstance(row, Mapping):
            raise StitchExpansionError(
                f"abstraction {position} must be a mapping"
            )
        name = row.get("name")
        arity = row.get("arity")
        body_source = row.get("body")
        if not isinstance(name, str) or not name:
            raise StitchExpansionError(
                f"abstraction {position} has invalid name"
            )
        if any(char.isspace() or char in "()" for char in name):
            raise StitchExpansionError(
                f"abstraction {name!r} is not an atom"
            )
        if name in definitions:
            raise StitchExpansionError(
                f"duplicate abstraction definition: {name}"
            )
        if type(arity) is not int or arity < 0:
            raise StitchExpansionError(
                f"abstraction {name} has invalid arity"
            )
        if not isinstance(body_source, str):
            raise StitchExpansionError(
                f"abstraction {name} has non-string body"
            )
        body = parse_sexpr(body_source)
        invalid = sorted(
            variable
            for variable in set(_walk_variables(body))
            if variable >= arity
        )
        if invalid:
            raise StitchExpansionError(
                f"abstraction {name} references variables outside arity: "
                + ",".join(f"#{variable}" for variable in invalid)
            )
        definitions[name] = Abstraction(name, arity, body)
    return definitions


def _substitute(node: Node, arguments: tuple[Node, ...]) -> Node:
    """Perform simultaneous positional substitution over an immutable AST."""

    if isinstance(node, str):
        match = _VARIABLE.fullmatch(node)
        if match:
            position = int(match.group(1))
            if position >= len(arguments):
                raise StitchExpansionError(
                    f"unresolved abstraction variable #{position}"
                )
            return arguments[position]
        return node
    return tuple(_substitute(child, arguments) for child in node)


def expand_program_detailed(
    rewritten: str,
    abstraction_rows: Sequence[Mapping[str, object]],
    *,
    max_expansions: int = _DEFAULT_MAX_EXPANSIONS,
    max_depth: int = _DEFAULT_MAX_DEPTH,
) -> ExpansionResult:
    """Expand all named abstractions and return canonical source plus counts."""

    if type(max_expansions) is not int or max_expansions < 1:
        raise StitchExpansionError(
            "max_expansions must be a positive integer"
        )
    definitions = load_abstractions(abstraction_rows)
    root = parse_sexpr(rewritten, max_depth=max_depth)
    counts = {name: 0 for name in definitions}
    budget = [max_expansions]

    def expand(node: Node, active: tuple[str, ...], depth: int) -> Node:
        if depth > max_depth:
            raise StitchExpansionError("expansion nesting limit exceeded")
        if isinstance(node, str):
            if _VARIABLE.fullmatch(node):
                raise StitchExpansionError(
                    f"unbound variable in rewritten program: {node}"
                )
            return node
        if node and isinstance(node[0], str) and node[0] in definitions:
            name = node[0]
            definition = definitions[name]
            supplied = len(node) - 1
            accepts_continuation = (
                definition.has_open_sequence_continuation
                and supplied == definition.arity + 1
            )
            if supplied != definition.arity and not accepts_continuation:
                suffix = (
                    " or one additional sequence continuation"
                    if definition.has_open_sequence_continuation
                    else ""
                )
                raise StitchExpansionError(
                    f"{name} expects {definition.arity} arguments{suffix}, "
                    f"received {supplied}"
                )
            if name in active:
                cycle = " -> ".join((*active, name))
                raise StitchExpansionError(
                    f"recursive abstraction expansion: {cycle}"
                )
            if budget[0] == 0:
                raise StitchExpansionError("abstraction expansion limit exceeded")
            budget[0] -= 1
            counts[name] += 1
            # Expand arguments first.  Substitution is then simultaneous, so an
            # argument cannot capture or alter another argument.
            arguments = tuple(
                expand(child, active, depth + 1)
                for child in node[1 : definition.arity + 1]
            )
            substituted = _substitute(definition.body, arguments)
            if accepts_continuation:
                continuation = expand(node[-1], active, depth + 1)
                assert isinstance(substituted, tuple)
                substituted = (*substituted, continuation)
            return expand(substituted, (*active, name), depth + 1)
        return tuple(
            expand(child, active, depth + 1) for child in node
        )

    expanded = _normalize_singleton_applications(expand(root, (), 1))
    return ExpansionResult(format_sexpr(expanded), dict(counts))


def expand_program(
    rewritten: str,
    definitions: Sequence[Mapping[str, object]],
    *,
    max_expansions: int = _DEFAULT_MAX_EXPANSIONS,
    max_depth: int = _DEFAULT_MAX_DEPTH,
) -> tuple[str, int]:
    """Return ``(canonical_expansion, total_abstraction_invocations)``."""

    result = expand_program_detailed(
        rewritten,
        definitions,
        max_expansions=max_expansions,
        max_depth=max_depth,
    )
    return result.expanded, result.total_expansions


def verify_normalized_reconstruction(
    original: str,
    rewritten: str,
    abstraction_rows: Sequence[Mapping[str, object]],
    **limits: int,
) -> ExpansionResult:
    """Require byte-identical normalized canonical reconstruction."""

    result = expand_program_detailed(rewritten, abstraction_rows, **limits)
    normalized_original = canonicalize_stitch(original)
    if result.expanded != normalized_original:
        raise StitchExpansionError(
            "expanded rewrite is not byte-identical to normalized original: "
            f"expanded_bytes={len(result.expanded.encode())} "
            f"normalized_original_bytes="
            f"{len(normalized_original.encode())}"
        )
    return result


def verify_reconstruction(
    original: str,
    rewritten: str,
    abstraction_rows: Sequence[Mapping[str, object]],
    **limits: int,
) -> ExpansionResult:
    """Backward-compatible name for normalized canonical verification."""

    return verify_normalized_reconstruction(
        original, rewritten, abstraction_rows, **limits
    )


def _expect_error(fragment: str, function: object, *args: object) -> None:
    try:
        function(*args)  # type: ignore[operator]
    except StitchExpansionError as error:
        if fragment not in str(error):
            raise AssertionError(
                f"expected error containing {fragment!r}, got {error!r}"
            ) from error
    else:
        raise AssertionError(f"expected StitchExpansionError: {fragment}")


def _self_test() -> None:
    rows = [
        {
            "name": "fn_0",
            "arity": 3,
            "body": "(seq (call #2 #1 #0 dict))",
        }
    ]
    rewritten = (
        "(seq (fn_0 (tuple (ref back_1) lit_a) tensor_r2 aten_relu) "
        "(outputs (ref back_1)))"
    )
    raw_original = (
        "(seq (seq (call aten_relu tensor_r2 "
        "(tuple (ref back_1) lit_a) (dict ))) "
        "(outputs (ref back_1)))"
    )
    result = verify_normalized_reconstruction(
        raw_original, rewritten, rows
    )
    assert result.counts == {"fn_0": 1}
    assert result.total_expansions == 1
    assert format_sexpr(parse_sexpr(" (a   (b c)) ")) == "(a (b c))"
    chained_rewrite = (
        "(fn_0 (tuple x) type_a op_a "
        "(fn_0 (tuple (ref back_1)) type_b op_b (outputs)))"
    )
    chained_raw_original = (
        "(seq (call op_a type_a (tuple x) (dict )) "
        "(seq (call op_b type_b (tuple (ref back_1)) (dict )) "
        "(outputs )))"
    )
    chained = verify_normalized_reconstruction(
        chained_raw_original, chained_rewrite, rows
    )
    assert chained.total_expansions == 2

    nested_rows = [
        {"name": "inner", "arity": 1, "body": "(wrap #0)"},
        {"name": "outer", "arity": 1, "body": "(inner (pair #0 #0))"},
    ]
    nested = expand_program_detailed("(outer value)", nested_rows)
    assert nested.expanded == "(wrap (pair value value))"
    assert nested.counts == {"inner": 1, "outer": 1}

    _expect_error("unclosed", parse_sexpr, "(a")
    _expect_error("trailing", parse_sexpr, "a b")
    _expect_error(
        "outside arity",
        load_abstractions,
        [{"name": "bad", "arity": 1, "body": "(x #1)"}],
    )
    _expect_error(
        "expects 3",
        expand_program,
        "(fn_0 only_two args)",
        rows,
    )
    _expect_error(
        "unbound variable",
        expand_program,
        "(plain #0)",
        rows,
    )
    _expect_error(
        "recursive",
        expand_program,
        "(loop x)",
        [{"name": "loop", "arity": 1, "body": "(loop #0)"}],
    )
    _expect_error(
        "byte-identical",
        verify_normalized_reconstruction,
        "(wrong)",
        rewritten,
        rows,
    )


if __name__ == "__main__":
    _self_test()
    print(
        "INDEPENDENT_STITCH_EXPANDER_SELF_TEST "
        "status=PASS semantics=positional_simultaneous_substitution"
    )
