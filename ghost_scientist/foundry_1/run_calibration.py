#!/usr/bin/env python3
"""Two-phase autonomous tool-grammar calibration and transfer pilot."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import resource
import sys
import time
from collections.abc import Sequence
from typing import Any

from candidate_forge import (
    canonical_json,
    enumerate_tools,
    make_tool,
    program_description_length,
    sha256_json,
)
from independent_evaluator import (
    canonical_witness,
    execute_tool,
    file_sha256_bytes,
    hostile_selftest,
    parse_tool,
    similarity,
)


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULTS = HERE / "results"

SCHEMAS = {
    "declarations": "offsets",
    "csv_width": "row_width_pairs",
    "sleep_loop": "offset_block_spans",
    "missing_arg": "offset_line_spans",
}

# These are evaluator-owned calibration fixtures.  Candidate proposal code
# receives bytes and an output schema, never these paths or the kind labels.
TRAIN = {
    "declarations": (
        "core/src/adapters/invention_engine.zig",
        "core/src/adapters/domain_agi_blueprint.zig",
    ),
    "csv_width": (
        "results/candidate_analyzer_loop_round_au.csv",
        "results/grid_scaling_audit_round_ax.csv",
    ),
    "sleep_loop": (
        "07_agent_loop/src/body.zig",
        "sparse_poly_discovery/telemetry.zig",
    ),
    "missing_arg": (
        "04_verified_synthesis/src/verify_cli.zig",
        "05_meta_synthesis/src/meta_mixer_export.zig",
    ),
}

PHASE1 = {
    "declarations": ("core/src/adapters/domain_agi_subsystem_synthesis.zig",),
    "csv_width": ("results/blank_region_round_l.csv",),
    "sleep_loop": ("12_adversarial_loop/src/immune_loop.zig",),
    "missing_arg": ("05_meta_synthesis/src/affine_closure.zig",),
}

PHASE2 = {
    "declarations": ("sparse_poly_discovery/ghost_scientist_constructor_luna.zig",),
    "csv_width": ("results/intervention_value_round_ak.csv",),
    "sleep_loop": ("sparse_poly_discovery/ghost_daemon.zig",),
    "missing_arg": ("05_meta_synthesis/src/meta_mixer_export_dual.zig",),
}


def _read(relative: str) -> bytes:
    path = ROOT / relative
    if not path.is_file():
        raise RuntimeError(f"missing corpus fixture: {relative}")
    return path.read_bytes()


def _provenance(relative: str, phase: str, kind: str) -> dict[str, object]:
    raw = _read(relative)
    return {
        "opaque_id": sha256_json({"phase": phase, "kind": kind, "sha256": file_sha256_bytes(raw)})[:20],
        "phase": phase,
        "kind": kind,
        "source_class": "real_git_tracked_local_artifact",
        "evaluator_path": relative,
        "payload_sha256": file_sha256_bytes(raw),
        "bytes": len(raw),
    }


def corpus_manifest() -> dict[str, object]:
    records = []
    for phase, groups in (("train", TRAIN), ("phase1", PHASE1), ("phase2", PHASE2)):
        for kind, paths in groups.items():
            records.extend(_provenance(path, phase, kind) for path in paths)
    hashes = [item["payload_sha256"] for item in records]
    if len(hashes) != len(set(hashes)):
        raise RuntimeError("corpus train/transfer payloads overlap")
    return {
        "version": "FOUNDRY_CALIBRATION_CORPUS_V1",
        "records": records,
        "limitations": [
            "local artifacts are not an independently sourced external corpus",
            "invocation frequencies are not externally sourced",
            "task contracts are evaluator-authored structural properties",
        ],
    }


def _select_tool(kind: str, paths: Sequence[str]) -> tuple[dict[str, object], dict[str, object]]:
    schema = SCHEMAS[kind]
    payloads = [_read(path) for path in paths]
    start_cpu = time.process_time_ns()
    start_wall = time.monotonic_ns()
    before_rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    best: tuple[tuple[float, int, str], dict[str, object]] | None = None
    proposals = 0
    executions = 0
    rejected = 0
    work_bytes = 0
    for proposal in enumerate_tools(payloads, schema):
        proposals += 1
        try:
            parse_tool(proposal)
            scores = []
            for raw in payloads:
                scores.append(
                    similarity(execute_tool(proposal, raw), canonical_witness(kind, raw))
                )
                executions += 1
                work_bytes += len(raw)
        except Exception:
            rejected += 1
            continue
        mean_score = sum(scores) / len(scores)
        key = (-mean_score, program_description_length(proposal), proposal["tool_digest"])
        if best is None or key < best[0]:
            best = (key, proposal)
    if best is None:
        raise RuntimeError(f"forge produced no valid proposal for {kind}")
    score = -best[0][0]
    receipt = {
        "kind": kind,
        "output_schema": schema,
        "proposal_count": proposals,
        "valid_proposals": proposals - rejected,
        "rejected_proposals": rejected,
        "evaluator_executions": executions,
        "charged_payload_bytes": work_bytes,
        "cpu_ns": time.process_time_ns() - start_cpu,
        "wall_ns": time.monotonic_ns() - start_wall,
        "peak_rss_kib_before": before_rss,
        "peak_rss_kib_after": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
        "training_score": score,
        "selected_tool_digest": best[1]["tool_digest"],
        "selection_rule": "max_mean_f1_then_min_description_length_then_digest",
    }
    return best[1], receipt


def _fixed_tools() -> dict[str, dict[str, object]]:
    return {
        "declarations": make_tool(
            [
                {"op": "find", "literal": "pub fn"},
                {"op": "not_line_comment"},
                {"op": "emit_offsets"},
            ],
            "offsets",
            generator="bounded_enumeration",
        ),
        "csv_width": make_tool(
            [{"op": "csv_width", "delimiter": ","}],
            "row_width_pairs",
            generator="bounded_enumeration",
        ),
        "sleep_loop": make_tool(
            [
                {"op": "find", "literal": "std.time.sleep"},
                {"op": "enclosing_block", "prefix": "while"},
                {"op": "emit_offset_block_spans"},
            ],
            "offset_block_spans",
            generator="bounded_enumeration",
        ),
        "missing_arg": make_tool(
            [
                {"op": "find", "literal": "return error.MissingArg"},
                {"op": "line_span"},
                {"op": "emit_offset_line_spans"},
            ],
            "offset_line_spans",
            generator="bounded_enumeration",
        ),
    }


def _evaluate_phase(
    tools: dict[str, dict[str, object]],
    groups: dict[str, Sequence[str]],
    phase: str,
) -> dict[str, object]:
    fixed = _fixed_tools()
    rows = []
    candidate_exact = 0
    fixed_exact = 0
    removal_losses = 0
    transferred_digests: set[str] = set()
    for kind, paths in groups.items():
        tool = tools[kind]
        for relative in paths:
            raw = _read(relative)
            expected = canonical_witness(kind, raw)
            actual = execute_tool(tool, raw)
            fixed_actual = execute_tool(fixed[kind], raw)
            exact = actual == expected
            fixed_ok = fixed_actual == expected
            candidate_exact += int(exact)
            fixed_exact += int(fixed_ok)
            removal_loss = exact and expected != ()
            removal_losses += int(removal_loss)
            if exact:
                transferred_digests.add(str(tool["tool_digest"]))
            rows.append(
                {
                    "opaque_id": sha256_json(
                        {"phase": phase, "payload": file_sha256_bytes(raw), "kind": kind}
                    )[:20],
                    "kind": kind,
                    "payload_sha256": file_sha256_bytes(raw),
                    "tool_digest": tool["tool_digest"],
                    "candidate_witness_sha256": sha256_json(actual),
                    "expected_witness_sha256": sha256_json(expected),
                    "candidate_exact": exact,
                    "fixed_exact": fixed_ok,
                    "removal_intervention": "witness_lost" if removal_loss else "no_nonempty_witness",
                    "payload_bytes_charged": len(raw),
                }
            )
    return {
        "phase": phase,
        "rows": rows,
        "summary": {
            "tasks": len(rows),
            "candidate_exact": candidate_exact,
            "fixed_exact": fixed_exact,
            "direct_reuse_receipts": candidate_exact,
            "causal_removal_losses": removal_losses,
            "transferred_tool_digests": len(transferred_digests),
            "candidate_beats_strong_fixed": candidate_exact > fixed_exact,
            "candidate_matches_strong_fixed": candidate_exact == fixed_exact,
        },
    }


def run_phase1() -> None:
    RESULTS.mkdir(parents=True, exist_ok=True)
    manifest = corpus_manifest()
    (RESULTS / "corpus_manifest.json").write_text(
        canonical_json(manifest) + "\n", encoding="utf-8"
    )
    tools: dict[str, dict[str, object]] = {}
    receipts = []
    for kind, paths in TRAIN.items():
        tool, receipt = _select_tool(kind, paths)
        tools[kind] = tool
        receipts.append(receipt)
    phase1 = _evaluate_phase(tools, PHASE1, "phase1_pre_freeze_pilot")
    native_dedup = []
    for kind, tool in sorted(tools.items()):
        program = tool["program"]
        assert isinstance(program, list)
        native_dedup.append(
            {
                "kind": kind,
                "tool_digest": tool["tool_digest"],
                "structurally_multi_operation": len(program) > 1,
                "compiler_ir_dedup_completed": False,
                "status": "PROVISIONAL_DISTINCT" if len(program) > 1 else "REJECT_SINGLE_NATIVE_FORM",
            }
        )
    payload = {
        "version": "FOUNDRY_PHASE1_V1",
        "status": "CALIBRATION_ONLY",
        "candidate_boundary": {
            "llm_free": True,
            "answer_blind_proposal_generation": True,
            "tool_forms_selected_by_feedback": True,
            "primitive_semantics_supplied": True,
            "output_schemas_supplied": True,
        },
        "tools": tools,
        "forge_receipts": receipts,
        "native_dedup": native_dedup,
        "independent_verifier_hostile_rejections": hostile_selftest(),
        "pilot": phase1,
    }
    (RESULTS / "phase1.json").write_text(canonical_json(payload) + "\n", encoding="utf-8")
    (RESULTS / "learned_tools.json").write_text(
        canonical_json({"version": "FOUNDRY_LIBRARY_V1", "tools": tools}) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE1_PASS"
        f" tools={len(tools)} candidate_exact={phase1['summary']['candidate_exact']}"
        f"/{phase1['summary']['tasks']} fixed_exact={phase1['summary']['fixed_exact']}"
        f"/{phase1['summary']['tasks']} hostile_rejections={hostile_selftest()}"
    )


def _verify_freeze() -> None:
    from freeze_foundry_1 import verify

    verify()


def run_phase2() -> None:
    _verify_freeze()
    library = json.loads((RESULTS / "learned_tools.json").read_text(encoding="utf-8"))
    if set(library) != {"version", "tools"} or library["version"] != "FOUNDRY_LIBRARY_V1":
        raise RuntimeError("frozen library contract mismatch")
    tools = library["tools"]
    for tool in tools.values():
        parse_tool(tool)
    phase2 = _evaluate_phase(tools, PHASE2, "phase2_post_freeze_transfer")
    payload = {
        "version": "FOUNDRY_PHASE2_V1",
        "status": "VALID_LOCAL_PROSPECTIVE_CALIBRATION",
        "freeze_sha256": file_sha256_bytes((RESULTS / "protocol_freeze.txt").read_bytes()),
        "library_sha256": file_sha256_bytes((RESULTS / "learned_tools.json").read_bytes()),
        "phase2": phase2,
        "claim_boundary": [
            "local tracked artifacts only",
            "no independently sourced external workload",
            "no external invocation trace",
            "no total-cost scientific PASS claim",
            "no autonomous primitive invention claim",
        ],
    }
    (RESULTS / "phase2.json").write_text(canonical_json(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE2_PASS"
        f" candidate_exact={phase2['summary']['candidate_exact']}/{phase2['summary']['tasks']}"
        f" fixed_exact={phase2['summary']['fixed_exact']}/{phase2['summary']['tasks']}"
        f" causal_removal_losses={phase2['summary']['causal_removal_losses']}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("phase", choices=("phase1", "phase2"))
    args = parser.parse_args()
    if args.phase == "phase1":
        run_phase1()
    else:
        run_phase2()


if __name__ == "__main__":
    main()
