#!/usr/bin/env python3
"""Independently audit the semantics of the A5 Stitch rewrite.

This deliberately does not reuse the primary A5 encoder or any expansion
implementation from the production mount.  It reruns the source-faithful
Stitch binary over the independently encoded 23-graph calibration corpus,
then expands the learned abstraction with a small, separately implemented
S-expression evaluator.
"""

from __future__ import annotations

from collections.abc import Iterable
import hashlib
import json
import os
import pathlib
import re
import subprocess
from typing import TypeAlias

import torch

from independent_a5_stitch_graph_encoder import (
    encode_graph as independent_encode,
)
from phase63_pareto_motif_calibration import workloads


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE / "arm_adapter_fixtures/A5_STITCH_TYPED_GRAPH_PROTOCOL_V1.json"
)
BINARY = (
    HERE
    / "external_controls/stitch/source/target/release/"
    "foundry-stitch-control"
)
SOURCE_RESULT = HERE / "results/phase35_stitch_source_control.json"
PHASE99_RESULT = HERE / "results/phase99_a5_stitch_typed_graph_audit.json"

SExpr: TypeAlias = str | list["SExpr"]
TOKEN = re.compile(r"\(|\)|[^\s()]+")
IVAR = re.compile(r"#([0-9]+)\Z")


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_sexpr(text: str, *, collapse_singletons: bool) -> SExpr:
    """Parse the Stitch surface syntax without depending on Stitch's parser.

    Stitch represents application by whitespace-separated, left-associative
    list items.  Its parser treats a singleton parenthesized expression such
    as ``(dict )`` as the enclosed primitive.  ``collapse_singletons`` models
    that normalization explicitly.
    """

    tokens = TOKEN.findall(text)
    if not tokens:
        raise ValueError("empty S-expression")
    position = 0

    def parse_one() -> SExpr:
        nonlocal position
        if position >= len(tokens):
            raise ValueError("unexpected end of S-expression")
        token = tokens[position]
        position += 1
        if token == ")":
            raise ValueError("unexpected closing parenthesis")
        if token != "(":
            return token
        items: list[SExpr] = []
        while True:
            if position >= len(tokens):
                raise ValueError("unterminated parenthesized expression")
            if tokens[position] == ")":
                position += 1
                break
            items.append(parse_one())
        if not items:
            raise ValueError("empty parenthesized expression")
        if collapse_singletons and len(items) == 1:
            return items[0]
        return items

    parsed = parse_one()
    if position != len(tokens):
        raise ValueError("trailing S-expression tokens")
    return parsed


def format_sexpr(expr: SExpr) -> str:
    if isinstance(expr, str):
        return expr
    return "(" + " ".join(format_sexpr(item) for item in expr) + ")"


def walk(expr: SExpr) -> Iterable[SExpr]:
    yield expr
    if isinstance(expr, list):
        for item in expr:
            yield from walk(item)


def substitute_ivars(expr: SExpr, arguments: list[SExpr]) -> SExpr:
    if isinstance(expr, str):
        match = IVAR.fullmatch(expr)
        if match is None:
            return expr
        index = int(match.group(1))
        if index >= len(arguments):
            raise ValueError(f"unbound abstraction variable: {expr}")
        return arguments[index]
    return [substitute_ivars(item, arguments) for item in expr]


def expand_abstractions(
    expr: SExpr,
    abstractions: dict[str, tuple[int, SExpr]],
    *,
    depth: int = 0,
) -> SExpr:
    """Expand flattened left-associative Stitch invention applications."""

    if depth > 4096:
        raise ValueError("abstraction expansion depth exceeded")
    if isinstance(expr, str):
        return expr

    expanded_items = [
        expand_abstractions(item, abstractions, depth=depth + 1)
        for item in expr
    ]
    if not expanded_items or not isinstance(expanded_items[0], str):
        return expanded_items
    definition = abstractions.get(expanded_items[0])
    if definition is None:
        return expanded_items

    arity, body = definition
    if len(expanded_items) < arity + 1:
        raise ValueError(
            f"{expanded_items[0]} expects {arity} arguments, "
            f"received {len(expanded_items) - 1}"
        )
    arguments = expanded_items[1 : arity + 1]
    trailing_applications = expanded_items[arity + 1 :]
    substituted = substitute_ivars(body, arguments)
    if trailing_applications:
        if isinstance(substituted, list):
            substituted = [*substituted, *trailing_applications]
        else:
            substituted = [substituted, *trailing_applications]
    return expand_abstractions(
        substituted, abstractions, depth=depth + 1
    )


def count_named_invocations(expr: SExpr, name: str) -> int:
    return sum(
        1
        for node in walk(expr)
        if isinstance(node, list) and node and node[0] == name
    )


def call_kwargs_boundary(expr: SExpr) -> tuple[int, int]:
    """Return (empty kwargs calls, non-empty kwargs calls)."""

    empty = 0
    nonempty = 0
    for node in walk(expr):
        if (
            not isinstance(node, list)
            or len(node) != 5
            or node[0] != "call"
        ):
            continue
        kwargs = node[4]
        if kwargs == ["dict"]:
            empty += 1
        elif (
            isinstance(kwargs, list)
            and kwargs
            and kwargs[0] == "dict"
        ):
            nonempty += 1
        else:
            raise ValueError(f"unexpected encoded kwargs form: {kwargs!r}")
    return empty, nonempty


def run() -> dict[str, object]:
    protocol = json.loads(PROTOCOL.read_text(encoding="utf-8"))
    source_result = json.loads(SOURCE_RESULT.read_text(encoding="utf-8"))
    phase99 = json.loads(PHASE99_RESULT.read_text(encoding="utf-8"))
    if sha256(BINARY) != source_result["binary_sha256"]:
        raise RuntimeError("source-faithful Stitch binary hash mismatch")

    instantiated, unsupported = workloads()
    artifact_ids: list[str] = []
    programs: list[str] = []
    call_nodes = 0
    for suite, workload in instantiated:
        exported = torch.export.export(
            workload["model"],
            workload["args"],
            workload["kwargs"],
            strict=True,
        )
        program, metadata = independent_encode(exported.module().graph)
        artifact_ids.append(f"{suite}:{workload['family']}")
        programs.append(program)
        call_nodes += metadata["call_nodes"]

    call = {"programs": programs, **protocol["stitch_call"]}
    execution = subprocess.run(
        [str(BINARY)],
        cwd=HERE,
        env={**os.environ, "RAYON_NUM_THREADS": "1"},
        input=canonical(call),
        text=True,
        capture_output=True,
        timeout=60,
        check=False,
    )
    if execution.returncode != 0:
        raise RuntimeError(
            "source-faithful Stitch execution failed: "
            + execution.stderr[-2000:]
        )
    observed = json.loads(execution.stdout.strip().splitlines()[-1])
    rewritten: list[str] = observed["rewritten"]
    abstraction_rows: list[dict[str, object]] = observed["abstractions"]
    abstractions = {
        str(row["name"]): (
            int(row["arity"]),
            parse_sexpr(str(row["body"]), collapse_singletons=True),
        )
        for row in abstraction_rows
    }

    artifact_rows: list[dict[str, object]] = []
    normalized_equal = 0
    raw_equal = 0
    total_uses = 0
    empty_kwargs = 0
    nonempty_kwargs = 0
    for artifact_id, original, compressed in zip(
        artifact_ids, programs, rewritten, strict=True
    ):
        original_raw_ast = parse_sexpr(
            original, collapse_singletons=False
        )
        original_normalized_ast = parse_sexpr(
            original, collapse_singletons=True
        )
        rewritten_ast = parse_sexpr(
            compressed, collapse_singletons=True
        )
        expanded_ast = expand_abstractions(rewritten_ast, abstractions)
        expanded_text = format_sexpr(expanded_ast)
        normalized_text = format_sexpr(original_normalized_ast)
        uses = sum(
            count_named_invocations(rewritten_ast, name)
            for name in abstractions
        )
        artifact_empty, artifact_nonempty = call_kwargs_boundary(
            original_raw_ast
        )
        normalized_match = expanded_text == normalized_text
        raw_match = expanded_text == original
        normalized_equal += int(normalized_match)
        raw_equal += int(raw_match)
        total_uses += uses
        empty_kwargs += artifact_empty
        nonempty_kwargs += artifact_nonempty
        artifact_rows.append(
            {
                "artifact_id": artifact_id,
                "abstraction_invocations": uses,
                "empty_kwargs_calls": artifact_empty,
                "nonempty_kwargs_calls": artifact_nonempty,
                "normalized_expansion_equal": normalized_match,
                "raw_encoder_bytes_equal": raw_match,
            }
        )

    rewritten_sha256 = hashlib.sha256(
        canonical(rewritten).encode()
    ).hexdigest()
    reported_uses = sum(
        int(row["num_uses"]) for row in abstraction_rows
    )
    unique_use_rows = sum(
        len(row["uses"]) for row in abstraction_rows
    )
    checks = {
        "source_binary_authenticated": True,
        "complete_corpus_23_337": (
            len(programs) == 23
            and call_nodes == 337
            and len(rewritten) == 23
        ),
        "one_unsupported_explicit": len(unsupported) == 1,
        "one_abstraction_observed": len(abstraction_rows) == 1,
        "phase99_rewritten_hash_reproduced": (
            rewritten_sha256
            == phase99["observed"]["rewritten_sha256"]
        ),
        "normalized_expansion_23_of_23": normalized_equal == 23,
        "raw_encoder_equality_0_of_23": raw_equal == 0,
        "invocation_count_matches_reported_329": (
            total_uses == reported_uses == 329
        ),
        "empty_kwargs_boundary_329": empty_kwargs == 329,
        "nonempty_kwargs_boundary_8": nonempty_kwargs == 8,
        "all_and_only_empty_kwargs_calls_abstracted": (
            total_uses == empty_kwargs
            and empty_kwargs + nonempty_kwargs == call_nodes
        ),
        "unique_use_rows_not_misreported_as_executions": (
            unique_use_rows == 119 and unique_use_rows != total_uses
        ),
    }
    if not all(checks.values()):
        raise RuntimeError(
            "independent A5 Stitch semantics audit failed: "
            + canonical(
                {
                    "failed": [
                        name
                        for name, passed in checks.items()
                        if not passed
                    ]
                }
            )
        )

    return {
        "version": "INDEPENDENT_A5_STITCH_SEMANTICS_AUDIT_V1",
        "status": "PASS",
        "checks": checks,
        "source_faithful_binary_sha256": sha256(BINARY),
        "rewritten_sha256": rewritten_sha256,
        "abstraction": {
            "name": abstraction_rows[0]["name"],
            "arity": abstraction_rows[0]["arity"],
            "body": abstraction_rows[0]["body"],
            "reported_uses": reported_uses,
            "counted_rewritten_invocations": total_uses,
            "unique_structural_use_rows": unique_use_rows,
        },
        "semantic_boundary": {
            "normalized_expansion_equal": normalized_equal,
            "raw_encoder_bytes_equal": raw_equal,
            "empty_kwargs_calls": empty_kwargs,
            "nonempty_kwargs_calls": nonempty_kwargs,
            "finding": (
                "fn_0 is an empty-kwargs call/sequence scaffold; "
                "raw inequality is solely expected Stitch parser "
                "normalization of singleton `(dict )` to `dict`"
            ),
        },
        "artifacts": artifact_rows,
    }


if __name__ == "__main__":
    print(canonical(run()))
