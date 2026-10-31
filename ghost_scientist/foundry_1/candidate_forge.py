#!/usr/bin/env python3
"""Answer-blind typed text-tool proposal generator for Foundry-1.

This module never imports the evaluator.  It receives calibration payload
bytes and an output schema, then enumerates bounded programs over a small
frozen byte/text substrate.  Selection happens through evaluator-owned scalar
feedback in run_calibration.py.
"""

from __future__ import annotations

import hashlib
import json
import re
from collections import Counter
from collections.abc import Iterable, Sequence
from typing import Any


VERSION = "FOUNDRY_TOOL_V1"
OUTPUT_SCHEMAS = {
    "offsets",
    "row_width_pairs",
    "offset_block_spans",
    "offset_line_spans",
}


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def sha256_json(value: object) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def _token_ngrams(payloads: Sequence[bytes]) -> list[str]:
    counts: Counter[str] = Counter()
    token_pattern = re.compile(
        r"[A-Za-z_][A-Za-z0-9_.]*|==|!=|<=|>=|=>|->|[{}(),;:]"
    )
    for raw in payloads:
        text = raw.decode("utf-8", "replace")
        for line in text.splitlines():
            if len(line) > 512:
                continue
            tokens = token_pattern.findall(line)
            for width in (1, 2, 3):
                for start in range(0, len(tokens) - width + 1):
                    literal = " ".join(tokens[start : start + width])
                    if 2 <= len(literal) <= 64:
                        counts[literal] += 1
    # Retain every short or repeated fragment.  The ordering is deterministic
    # and does not depend on an answer, score, task family, or source path.
    selected = [
        literal
        for literal, count in counts.items()
        if count >= 2 or len(literal) <= 32 or "." in literal
    ]
    return sorted(set(selected), key=lambda item: (len(item), item))


def _contract(program: Sequence[dict[str, Any]], output_schema: str) -> dict[str, object]:
    constraints = ["input_is_immutable_bytes", "deterministic", "offsets_in_bounds"]
    operations = {step["op"] for step in program}
    if "not_line_comment" in operations:
        constraints.append("line_comment_mask_precedes_filter")
    if "enclosing_block" in operations:
        constraints.extend(("balanced_brace_witness", "match_inside_enclosing_block"))
    if "csv_width" in operations:
        constraints.extend(("header_defines_width", "blank_final_row_ignored"))
    if "line_span" in operations:
        constraints.append("span_contains_match")
    return {
        "input": "bytes",
        "output": output_schema,
        "constraints": sorted(constraints),
    }


def make_tool(
    program: Sequence[dict[str, Any]],
    output_schema: str,
    *,
    generator: str,
) -> dict[str, object]:
    if output_schema not in OUTPUT_SCHEMAS:
        raise ValueError(f"unsupported output schema {output_schema}")
    core = {
        "version": VERSION,
        "generator": generator,
        "program": list(program),
        "contract": _contract(program, output_schema),
    }
    return {**core, "tool_digest": sha256_json(core)}


def enumerate_tools(payloads: Sequence[bytes], output_schema: str) -> Iterable[dict[str, object]]:
    """Enumerate tools without evaluator results or task-family labels."""
    literals = _token_ngrams(payloads)
    if output_schema == "row_width_pairs":
        for delimiter in (",", ";", "\t", "|"):
            yield make_tool(
                [{"op": "csv_width", "delimiter": delimiter}],
                output_schema,
                generator="bounded_enumeration",
            )
        return

    if output_schema == "offsets":
        for literal in literals:
            source = {"op": "find", "literal": literal}
            yield make_tool(
                [source, {"op": "emit_offsets"}],
                output_schema,
                generator="bounded_enumeration",
            )
            yield make_tool(
                [source, {"op": "not_line_comment"}, {"op": "emit_offsets"}],
                output_schema,
                generator="bounded_enumeration",
            )
        return

    if output_schema == "offset_line_spans":
        for literal in literals:
            yield make_tool(
                [
                    {"op": "find", "literal": literal},
                    {"op": "line_span"},
                    {"op": "emit_offset_line_spans"},
                ],
                output_schema,
                generator="bounded_enumeration",
            )
        return

    if output_schema == "offset_block_spans":
        block_prefixes = [
            literal
            for literal in literals
            if literal in {"while", "while (", "for", "for ("}
        ]
        # These syntax forms are substrate tokens, not task answers.
        block_prefixes.extend(("while", "while (", "for", "for ("))
        for literal in literals:
            for prefix in sorted(set(block_prefixes)):
                yield make_tool(
                    [
                        {"op": "find", "literal": literal},
                        {"op": "enclosing_block", "prefix": prefix},
                        {"op": "emit_offset_block_spans"},
                    ],
                    output_schema,
                    generator="bounded_enumeration",
                )
        return

    raise ValueError(f"unsupported output schema {output_schema}")


def program_description_length(tool: dict[str, object]) -> int:
    program = tool["program"]
    assert isinstance(program, list)
    return len(canonical_json(program))

