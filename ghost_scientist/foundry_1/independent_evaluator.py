#!/usr/bin/env python3
"""Independent strict parser, interpreter, and evaluator for Foundry-1.

This module does not import candidate_forge.  It reconstructs tool digests,
contracts, canonical task witnesses, and hostile rejection behavior.
"""

from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping, Sequence
from typing import Any


VERSION = "FOUNDRY_TOOL_V1"
ALLOWED_OUTPUTS = {
    "offsets",
    "row_width_pairs",
    "offset_block_spans",
    "offset_line_spans",
}


class Reject(ValueError):
    pass


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def sha256_json(value: object) -> str:
    return hashlib.sha256(canonical_json(value).encode()).hexdigest()


def file_sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _exact(value: object, keys: set[str], context: str) -> Mapping[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise Reject(f"{context} fields are not fail-closed")
    return value


def _expected_contract(program: Sequence[Mapping[str, Any]], output: str) -> dict[str, object]:
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
    return {"input": "bytes", "output": output, "constraints": sorted(constraints)}


def parse_tool(raw: object) -> dict[str, Any]:
    root = _exact(
        raw,
        {"version", "generator", "program", "contract", "tool_digest"},
        "tool",
    )
    if root["version"] != VERSION or root["generator"] != "bounded_enumeration":
        raise Reject("tool identity is unsupported")
    digest = root["tool_digest"]
    if not isinstance(digest, str) or len(digest) != 64:
        raise Reject("tool digest is malformed")
    program = root["program"]
    contract = root["contract"]
    if not isinstance(program, list) or not 1 <= len(program) <= 4:
        raise Reject("program length is invalid")
    parsed: list[Mapping[str, Any]] = []
    for index, step in enumerate(program):
        if not isinstance(step, dict) or "op" not in step:
            raise Reject(f"step {index} is malformed")
        op = step["op"]
        if op == "find":
            item = _exact(step, {"op", "literal"}, f"step {index}")
            literal = item["literal"]
            if (
                not isinstance(literal, str)
                or not 2 <= len(literal) <= 64
                or any(term in literal.lower() for term in ("answer", "expected", "score="))
            ):
                raise Reject("find literal is unsafe")
        elif op == "enclosing_block":
            item = _exact(step, {"op", "prefix"}, f"step {index}")
            if item["prefix"] not in ("while", "while (", "for", "for ("):
                raise Reject("block prefix is outside the substrate")
        elif op == "csv_width":
            item = _exact(step, {"op", "delimiter"}, f"step {index}")
            if item["delimiter"] not in (",", ";", "\t", "|"):
                raise Reject("delimiter is outside the substrate")
        elif op in {
            "not_line_comment",
            "emit_offsets",
            "line_span",
            "emit_offset_line_spans",
            "emit_offset_block_spans",
        }:
            item = _exact(step, {"op"}, f"step {index}")
        else:
            raise Reject(f"operation {op!r} is unsupported")
        parsed.append(item)
    contract_map = _exact(contract, {"input", "output", "constraints"}, "contract")
    output = contract_map["output"]
    if output not in ALLOWED_OUTPUTS:
        raise Reject("output schema is unsupported")
    expected_contract = _expected_contract(parsed, output)
    if dict(contract_map) != expected_contract:
        raise Reject("typed contract does not match program")
    core = {
        "version": root["version"],
        "generator": root["generator"],
        "program": program,
        "contract": contract,
    }
    if sha256_json(core) != digest:
        raise Reject("tool digest does not bind its body")
    return dict(root)


def _find_all(raw: bytes, literal: str) -> list[int]:
    needle = literal.encode()
    positions: list[int] = []
    start = 0
    while True:
        at = raw.find(needle, start)
        if at < 0:
            return positions
        positions.append(at)
        start = at + len(needle)


def _line_comment_before(raw: bytes, position: int) -> bool:
    start = raw.rfind(b"\n", 0, position) + 1
    comment = raw.find(b"//", start, position)
    return comment >= 0


def _brace_end(raw: bytes, opening: int) -> int | None:
    depth = 0
    for index in range(opening, len(raw)):
        byte = raw[index]
        if byte == ord("{"):
            depth += 1
        elif byte == ord("}"):
            depth -= 1
            if depth == 0:
                return index
    return None


def execute_tool(tool_raw: object, raw: bytes) -> tuple[tuple[int, ...], ...]:
    tool = parse_tool(tool_raw)
    program = tool["program"]
    if len(program) == 1 and program[0]["op"] == "csv_width":
        delimiter = program[0]["delimiter"].encode()
        lines = raw.splitlines()
        if not lines:
            return ()
        header_width = lines[0].count(delimiter) + 1
        return tuple(
            (row, line.count(delimiter) + 1)
            for row, line in enumerate(lines[1:], start=1)
            if line and line.count(delimiter) + 1 != header_width
        )
    if not program or program[0]["op"] != "find":
        raise Reject("program has no valid source")
    positions = _find_all(raw, program[0]["literal"])
    current: object = positions
    for step in program[1:]:
        op = step["op"]
        if op == "not_line_comment":
            current = [item for item in current if not _line_comment_before(raw, item)]
        elif op == "line_span":
            current = [
                (item, raw.rfind(b"\n", 0, item) + 1, (raw.find(b"\n", item) if raw.find(b"\n", item) >= 0 else len(raw)))
                for item in current
            ]
        elif op == "enclosing_block":
            prefix = step["prefix"].encode()
            triples: list[tuple[int, int, int]] = []
            for item in current:
                block_start = raw.rfind(prefix, 0, item)
                if block_start < 0:
                    continue
                opening = raw.find(b"{", block_start, item + 1)
                if opening < 0:
                    continue
                ending = _brace_end(raw, opening)
                if ending is not None and item < ending:
                    triples.append((item, block_start, ending))
            current = triples
        elif op.startswith("emit_"):
            continue
        else:
            raise Reject("invalid execution sequence")
    if not isinstance(current, list):
        raise Reject("execution state is invalid")
    if current and isinstance(current[0], int):
        return tuple((item,) for item in current)
    return tuple(tuple(item) for item in current)


def canonical_witness(kind: str, raw: bytes) -> tuple[tuple[int, ...], ...]:
    if kind == "declarations":
        return tuple(
            (item,)
            for item in _find_all(raw, "pub fn ")
            if not _line_comment_before(raw, item)
        )
    if kind == "csv_width":
        lines = raw.splitlines()
        if not lines:
            return ()
        header_width = lines[0].count(b",") + 1
        return tuple(
            (row, line.count(b",") + 1)
            for row, line in enumerate(lines[1:], start=1)
            if line and line.count(b",") + 1 != header_width
        )
    if kind == "sleep_loop":
        triples = []
        for item in _find_all(raw, "std.time.sleep"):
            loop = raw.rfind(b"while (", 0, item)
            if loop < 0:
                continue
            opening = raw.find(b"{", loop, item + 1)
            ending = _brace_end(raw, opening) if opening >= 0 else None
            if ending is not None and item < ending:
                triples.append((item, loop, ending))
        return tuple(triples)
    if kind == "missing_arg":
        return tuple(
            (
                item,
                raw.rfind(b"\n", 0, item) + 1,
                raw.find(b"\n", item) if raw.find(b"\n", item) >= 0 else len(raw),
            )
            for item in _find_all(raw, "return error.MissingArg")
        )
    raise Reject(f"unknown evaluator task kind {kind}")


def similarity(actual: Sequence[tuple[int, ...]], expected: Sequence[tuple[int, ...]]) -> float:
    left, right = set(actual), set(expected)
    if not left and not right:
        return 1.0
    if not left or not right:
        return 0.0
    overlap = len(left & right)
    return 2.0 * overlap / (len(left) + len(right))


def hostile_selftest() -> int:
    valid = {
        "version": VERSION,
        "generator": "bounded_enumeration",
        "program": [{"op": "find", "literal": "pub fn"}, {"op": "emit_offsets"}],
        "contract": {
            "input": "bytes",
            "output": "offsets",
            "constraints": ["deterministic", "input_is_immutable_bytes", "offsets_in_bounds"],
        },
    }
    valid["tool_digest"] = sha256_json(valid)
    parse_tool(valid)
    mutations = [
        {**valid, "tool_digest": "0" * 64},
        {**valid, "answer": 3},
        {**valid, "program": [{"op": "find", "literal": "expected=3"}]},
        {**valid, "contract": {**valid["contract"], "output": "offset_line_spans"}},
    ]
    rejected = 0
    for mutation in mutations:
        try:
            parse_tool(mutation)
        except Reject:
            rejected += 1
    if rejected != len(mutations):
        raise AssertionError("hostile tool mutations were accepted")
    return rejected
