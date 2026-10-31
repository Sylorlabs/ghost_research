#!/usr/bin/env python3
"""Mount the frozen A5 Stitch calibration state on framework graphs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import resource
import subprocess
import time
from collections import Counter
from typing import Any

import torch

from a4_replay_runtime_mount import describe
from a5_stitch_graph_encoder import encode_graph as primary_encode
from independent_a5_stitch_graph_encoder import (
    encode_graph as independent_encode,
)
from independent_framework_runtime import (
    clone_tree,
    independent_assert,
    primary_compare,
)
from independent_stitch_expander import (
    canonicalize_stitch,
    verify_normalized_reconstruction,
)
from phase63_pareto_motif_calibration import old_repository, workloads


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE / "arm_adapter_fixtures/A5_STITCH_RUNTIME_MOUNT_PROTOCOL_V1.json"
)
LIBRARY = HERE / "results/a5_stitch_calibration_library_v1.json"
PHASE99 = HERE / "results/phase99_a5_stitch_typed_graph_audit.json"
BINARY = (
    HERE
    / "external_controls/stitch/source/target/release/"
    "foundry-stitch-control"
)


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def authenticate(protocol: dict) -> None:
    for row in protocol["provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"provider mismatch: {row['path']}")


def child_cpu_ns(before: resource.struct_rusage) -> int:
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    seconds = (
        after.ru_utime
        + after.ru_stime
        - before.ru_utime
        - before.ru_stime
    )
    return max(0, int(seconds * 1_000_000_000))


def run() -> dict:
    protocol = json.loads(PROTOCOL.read_text())
    authenticate(protocol)
    phase99 = json.loads(PHASE99.read_text())
    library_raw = LIBRARY.read_bytes()
    library = json.loads(library_raw)
    library_sha256 = hashlib.sha256(library_raw).hexdigest()
    definitions = library["definitions"]
    definition_sha256 = hashlib.sha256(
        canonical(definitions[0]).encode()
    ).hexdigest()
    selector_start = time.process_time_ns()
    expected_graphs = {
        row["artifact_id"]: row for row in phase99["graphs"]
    }
    selector_cpu_ns = time.process_time_ns() - selector_start

    instantiated, unsupported = workloads()
    prepared = []
    failures = list(unsupported)
    programs = []
    operators = set()
    calls = 0
    for suite, workload in instantiated:
        family = workload["family"]
        artifact_id = f"{suite}:{family}"
        compile_start = time.process_time_ns()
        try:
            exported = torch.export.export(
                workload["model"],
                workload["args"],
                workload["kwargs"],
                strict=True,
            )
            module = exported.module()
        except Exception as exc:
            failures.append(
                {
                    "suite": suite,
                    "family": family,
                    "exception_type": type(exc).__name__,
                }
            )
            continue
        compiler_cpu_ns = time.process_time_ns() - compile_start
        graph = module.graph
        encoding_start = time.process_time_ns()
        primary_program, primary_meta = primary_encode(graph)
        independent_program, independent_meta = independent_encode(graph)
        if (
            primary_program != independent_program
            or primary_meta != independent_meta
        ):
            raise RuntimeError(f"A5 encoder disagreement: {artifact_id}")
        expected = expected_graphs[artifact_id]
        if not (
            primary_meta["program_sha256"] == expected["program_sha256"]
            and primary_meta["call_nodes"] == expected["call_nodes"]
            and hashlib.sha256(str(graph).encode()).hexdigest()
            == expected["framework_graph_sha256"]
        ):
            raise RuntimeError(f"A5 graph drift: {artifact_id}")
        encoding_cpu_ns = time.process_time_ns() - encoding_start
        programs.append(primary_program)
        operators.update(primary_meta["operators"])
        calls += primary_meta["call_nodes"]
        prepared.append(
            {
                "suite": suite,
                "workload": workload,
                "artifact_id": artifact_id,
                "module": module,
                "graph": graph,
                "program": primary_program,
                "meta": primary_meta,
                "compiler_cpu_ns": compiler_cpu_ns,
                "encoding_cpu_ns": encoding_cpu_ns,
            }
        )

    call = {"programs": programs, **protocol["stitch_call"]}
    if hashlib.sha256(canonical(call).encode()).hexdigest() != protocol[
        "expected"
    ]["call_sha256"]:
        raise RuntimeError("A5 Stitch call drift")
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
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
    candidate_generation_cpu_ns = child_cpu_ns(before)
    if execution.returncode != 0:
        raise RuntimeError(
            "A5 Stitch runtime mount failed: " + execution.stderr[-2000:]
        )
    observed = json.loads(execution.stdout.strip().splitlines()[-1])
    rewritten = observed["rewritten"]
    rewritten_sha256 = hashlib.sha256(
        canonical(rewritten).encode()
    ).hexdigest()
    if not (
        observed["abstractions"]
        == phase99["observed"]["abstraction_rows"]
        and observed["original_cost"] == library["original_cost"]
        and observed["final_cost"] == library["final_cost"]
        and len(rewritten) == len(programs) == 23
        and rewritten_sha256 == library["rewritten_sha256"]
    ):
        raise RuntimeError("A5 Stitch calibration replay drift")

    rows = []
    totals = Counter()
    maximum_error = 0.0
    for index, item in enumerate(prepared):
        suite = item["suite"]
        workload = item["workload"]
        family = workload["family"]
        repository = workload.get(
            "repository", old_repository(suite, family)
        )
        domain = workload.get("semantic_domain", family)
        artifact_id = item["artifact_id"]
        verification_start = time.process_time_ns()
        expansion = verify_normalized_reconstruction(
            item["program"], rewritten[index], definitions
        )
        expanded = expansion.expanded
        uses = expansion.total_expansions
        normalized_original = canonicalize_stitch(item["program"])
        raw_equal = expanded == item["program"]
        verification_cpu_ns = (
            time.process_time_ns()
            - verification_start
            + item["encoding_cpu_ns"]
        )

        execution_start = time.process_time_ns()
        invocation_receipts = []
        artifact_error = 0.0
        aliases = True
        for ordinal in (1, 2, 3):
            seed = int.from_bytes(
                hashlib.sha256(
                    f"A5:{artifact_id}:{ordinal}".encode()
                ).digest()[:8],
                "big",
            ) % (2**31)
            torch.manual_seed(seed)
            with torch.no_grad():
                expected_output = workload["model"](
                    *clone_tree(workload["args"]),
                    **clone_tree(workload["kwargs"]),
                )
            torch.manual_seed(seed)
            with torch.no_grad():
                actual_output = item["module"](
                    *clone_tree(workload["args"]),
                    **clone_tree(workload["kwargs"]),
                )
            compared = primary_compare(expected_output, actual_output)
            independent_assert(expected_output, actual_output)
            artifact_error = max(
                artifact_error, compared["max_abs_error"]
            )
            aliases = aliases and compared[
                "alias_storage_checks_passed"
            ]
            invocation_receipts.append(
                {
                    "ordinal": ordinal,
                    "seed": seed,
                    "expected_sha256": compared["expected_sha256"],
                    "actual_sha256": compared["actual_sha256"],
                    "max_abs_error": compared["max_abs_error"],
                    "correct": compared["max_abs_error"] <= 1.0e-5,
                }
            )
        executed_cpu_ns = time.process_time_ns() - execution_start
        maximum_error = max(maximum_error, artifact_error)
        ledger = {
            "candidate_generation_cpu_ns": (
                candidate_generation_cpu_ns if index == 0 else 0
            ),
            "verification_cpu_ns": verification_cpu_ns,
            "compiler_cpu_ns": item["compiler_cpu_ns"],
            "selector_cpu_ns": selector_cpu_ns if index == 0 else 0,
            "executed_workload_cpu_ns": executed_cpu_ns,
            "failed_attempt_cpu_ns": 0,
        }
        ledger["total_cpu_ns"] = sum(ledger.values())
        source_sha256 = hashlib.sha256(
            canonical(
                {
                    "mount_id": protocol["mount_id"],
                    "suite": suite,
                    "family": family,
                    "repository": repository,
                    "providers": protocol["provider_records"],
                }
            ).encode()
        ).hexdigest()
        shape_seed_sha256 = hashlib.sha256(
            canonical(
                {
                    "args": describe(workload["args"]),
                    "kwargs": describe(workload["kwargs"]),
                    "base_seed": 0,
                }
            ).encode()
        ).hexdigest()
        rows.append(
            {
                "arm_id": "A5",
                "artifact_id": artifact_id,
                "family": family,
                "repository": repository,
                "semantic_domain": domain,
                "source_record_sha256": source_sha256,
                "graph_sha256": hashlib.sha256(
                    str(item["graph"]).encode()
                ).hexdigest(),
                "shape_seed_sha256": shape_seed_sha256,
                "state_before_sha256": library_sha256,
                "state_after_sha256": library_sha256,
                "library_retained_across_artifacts": True,
                "tool_receipts": [
                    {
                        "tool_sha256": definition_sha256,
                        "direct_use_count": uses,
                    }
                ],
                "rewritten_program_sha256": hashlib.sha256(
                    rewritten[index].encode()
                ).hexdigest(),
                "expanded_program_sha256": hashlib.sha256(
                    expanded.encode()
                ).hexdigest(),
                "normalized_original_sha256": hashlib.sha256(
                    normalized_original.encode()
                ).hexdigest(),
                "normalized_expansion_byte_identical": (
                    expanded == normalized_original
                ),
                "raw_encoder_bytes_identical": raw_equal,
                "invocation_receipts": invocation_receipts,
                "max_abs_error": artifact_error,
                "alias_storage_checks_passed": aliases,
                "cost_ledger": ledger,
            }
        )
        totals["calls"] += item["meta"]["call_nodes"]
        totals["uses"] += uses
        totals["executions"] += 3
        totals["cpu_ns"] += ledger["total_cpu_ns"]

    summary = {
        "graphs": len(rows),
        "unique_operator_targets": len(operators),
        "call_function_invocations": calls,
        "whole_graph_executions": totals["executions"],
        "unsupported_or_failed": len(failures),
        "abstractions": len(definitions),
        "structural_rewrite_uses": totals["uses"],
        "normalized_expansions_byte_identical": sum(
            row["normalized_expansion_byte_identical"] for row in rows
        ),
        "raw_encoder_bytes_identical": sum(
            row["raw_encoder_bytes_identical"] for row in rows
        ),
        "original_cost": observed["original_cost"],
        "final_cost": observed["final_cost"],
        "max_graph_abs_error": maximum_error,
        "candidate_generation_cpu_ns_charged_once": (
            candidate_generation_cpu_ns
        ),
        "cpu_ns": totals["cpu_ns"],
    }
    expected = protocol["expected"]
    passed = (
        summary["graphs"] == expected["graphs"]
        and summary["unique_operator_targets"]
        == expected["unique_operator_targets"]
        and summary["call_function_invocations"]
        == expected["call_function_invocations"]
        and summary["whole_graph_executions"]
        == expected["whole_graph_executions"]
        and summary["unsupported_or_failed"]
        == expected["unsupported_or_failed"]
        and summary["abstractions"] == expected["abstractions"]
        and summary["structural_rewrite_uses"]
        == expected["structural_rewrite_uses"]
        and summary["normalized_expansions_byte_identical"] == 23
        and summary["raw_encoder_bytes_identical"] == 0
        and summary["max_graph_abs_error"] <= 1.0e-5
        and sum(
            row["cost_ledger"]["candidate_generation_cpu_ns"] > 0
            for row in rows
        )
        == 1
    )
    if not passed:
        raise RuntimeError(
            "A5 runtime mount acceptance failed: " + canonical(summary)
        )
    return {
        "version": "FOUNDRY_A5_STITCH_RUNTIME_MOUNT_V1",
        "status": "A5_STITCH_RUNTIME_MOUNT_COMPONENT_PASS",
        "mount_id": protocol["mount_id"],
        "provider_records_authenticated": len(
            protocol["provider_records"]
        ),
        "library_sha256": library_sha256,
        "definition_sha256": definition_sha256,
        "rows": rows,
        "unsupported_or_failed": failures,
        "summary": summary,
        "scientific_boundary": {
            "normalized_textual_rewrite_reversibility_proven": True,
            "raw_encoder_byte_reversibility_proven": False,
            "normalization_only_difference": (
                "encoder nullary (dict ) applications become Stitch atom dict"
            ),
            "framework_export_numerical_parity_proven": True,
            "rewritten_stitch_program_executed_as_tensor_runtime": False,
            "new_tensor_primitive_discovered": False,
            "heldout_generalization_measured": False,
            "fixed_portfolio_beaten": False,
        },
        "integration": {
            "A5_runtime_mount_component_ready": True,
            "A5_production_integrated": False,
            "production_integrated_arms": 5,
        },
        "P3_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--summary-only", action="store_true")
    args = parser.parse_args()
    receipt = run()
    if args.summary_only:
        receipt = {
            "version": receipt["version"],
            "status": receipt["status"],
            "mount_id": receipt["mount_id"],
            "provider_records_authenticated": receipt[
                "provider_records_authenticated"
            ],
            "library_sha256": receipt["library_sha256"],
            "rows": len(receipt["rows"]),
            "summary": receipt["summary"],
            "scientific_boundary": receipt["scientific_boundary"],
            "A5_production_integrated": receipt["integration"][
                "A5_production_integrated"
            ],
            "P3_complete": receipt["P3_complete"],
            "validation_v6_accessed": receipt["validation_v6_accessed"],
        }
    print(canonical(receipt))


if __name__ == "__main__":
    main()
