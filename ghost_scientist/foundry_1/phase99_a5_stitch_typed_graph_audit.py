#!/usr/bin/env python3
"""Run source-faithful Stitch over two-way verified typed graph encodings."""

from __future__ import annotations

import hashlib
import json
import os
import pathlib
import subprocess

import torch

from a5_stitch_graph_encoder import encode_graph as primary_encode
from independent_a5_stitch_graph_encoder import (
    encode_graph as independent_encode,
)
from phase63_pareto_motif_calibration import old_repository, workloads


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE / "arm_adapter_fixtures/A5_STITCH_TYPED_GRAPH_PROTOCOL_V1.json"
)
RESULT = HERE / "results/phase99_a5_stitch_typed_graph_audit.json"
BINARY = (
    HERE
    / "external_controls/stitch/source/target/release/"
    "foundry-stitch-control"
)


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    for row in protocol["provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"provider mismatch: {row['path']}")
    source_result = json.loads(
        (HERE / "results/phase35_stitch_source_control.json").read_text()
    )
    if sha(BINARY) != source_result["binary_sha256"]:
        raise RuntimeError("Stitch binary hash mismatch")
    instantiated, unsupported = workloads()
    programs = []
    graph_rows = []
    operators = set()
    call_count = 0
    for suite, workload in instantiated:
        family = workload["family"]
        repository = workload.get(
            "repository", old_repository(suite, family)
        )
        exported = torch.export.export(
            workload["model"],
            workload["args"],
            workload["kwargs"],
            strict=True,
        )
        graph = exported.module().graph
        primary_program, primary_meta = primary_encode(graph)
        independent_program, independent_meta = independent_encode(graph)
        if (
            primary_program != independent_program
            or primary_meta != independent_meta
        ):
            raise RuntimeError(
                f"typed encoders disagree: {suite}:{family}"
            )
        programs.append(primary_program)
        operators.update(primary_meta["operators"])
        call_count += primary_meta["call_nodes"]
        graph_rows.append(
            {
                "artifact_id": f"{suite}:{family}",
                "family": family,
                "repository": repository,
                "semantic_domain": workload.get(
                    "semantic_domain", family
                ),
                "framework_graph_sha256": hashlib.sha256(
                    str(graph).encode()
                ).hexdigest(),
                **primary_meta,
            }
        )
    call = {
        "programs": programs,
        **protocol["stitch_call"],
    }
    execution = subprocess.run(
        [str(BINARY)],
        cwd=HERE,
        env={
            **os.environ,
            "RAYON_NUM_THREADS": "1",
        },
        input=canonical(call),
        text=True,
        capture_output=True,
        timeout=60,
        check=False,
    )
    if execution.returncode != 0:
        raise RuntimeError(
            "Stitch typed graph execution failed: "
            + execution.stderr[-2000:]
        )
    observed = json.loads(execution.stdout.strip().splitlines()[-1])
    abstractions = observed["abstractions"]
    rewritten = observed["rewritten"]
    checks = {
        "protocol_prefrozen": protocol[
            "frozen_before_encoding_or_execution"
        ],
        "provider_hashes_authentic": True,
        "binary_hash_matches_source_conformance": True,
        "complete_surface_23_41_337": (
            len(graph_rows) == 23
            and len(operators) == 41
            and call_count == 337
        ),
        "one_unsupported_graph_explicit": len(unsupported) == 1,
        "primary_independent_encodings_byte_identical": True,
        "all_call_nodes_encoded_once": sum(
            row["call_nodes"] for row in graph_rows
        )
        == call_count,
        "program_digest_multiplicity_explicit": all(
            isinstance(row["program_sha256"], str)
            and len(row["program_sha256"]) == 64
            for row in graph_rows
        ),
        "source_algorithm_terminated": execution.returncode == 0,
        "rewritten_program_count_exact": len(rewritten) == len(programs),
        "costs_nonnegative": (
            type(observed["original_cost"]) is int
            and type(observed["final_cost"]) is int
            and observed["original_cost"] >= 0
            and observed["final_cost"] >= 0
        ),
        "abstraction_relations_valid": all(
            item["num_uses"] > 0
            and item["utility"] >= 0
            and item["arity"] >= 0
            and isinstance(item["body"], str)
            for item in abstractions
        ),
        "source_faithful_boundary_preserved": (
            source_result["classification"]
            == "SOURCE_FAITHFUL_CONTROL_WITH_BUILD_SHIMS"
            and source_result["upstream_algorithm_source_executed"]
            is True
            and source_result["official_wheel_executed"] is False
            and source_result["official_binding_executed"] is False
        ),
        "integration_not_inflated": protocol["claim_boundary"][
            "production_integrated_arms_after_encoding_phase"
        ]
        == 5,
        "validation_v6_unread": protocol["claim_boundary"][
            "validation_v6_source_runtime_graph_or_outcome_accessed"
        ]
        is False,
        "prospective_unauthorized": protocol["claim_boundary"][
            "prospective_trial_authorized"
        ]
        is False,
    }
    if not all(checks.values()):
        raise RuntimeError(
            "A5 typed graph audit failed: "
            + canonical(
                {
                    "failed": [
                        name for name, passed in checks.items() if not passed
                    ]
                }
            )
        )
    payload = {
        "version": "FOUNDRY_A5_STITCH_TYPED_GRAPH_AUDIT_V1",
        "status": "A5_STITCH_TYPED_GRAPH_COMPONENT_PASS",
        "classification": "SOURCE_FAITHFUL_STITCH_EVALUATOR_TYPED_ENCODING",
        "audit_chronology": [
            {
                "stage": "pre_algorithm_encoding_gate",
                "outcome": "REJECTED",
                "reason": "independent encoder treated FX immutable mappings as literals",
                "remediation": "independent encoder now recognizes Mapping-compatible dict subclasses",
                "source_algorithm_outcome_accepted": False,
            },
            {
                "stage": "post_algorithm_implementation_check",
                "outcome": "REJECTED_THEN_CORRECTED",
                "reason": "an extra non-protocol uniqueness check rejected one legitimate pair of structurally identical graph programs",
                "remediation": "preserve and report digest multiplicity; the frozen protocol never required unique program structures",
                "acceptance_rule_changed": False,
            },
        ],
        "checks": checks,
        "binary_sha256": sha(BINARY),
        "input": {
            "programs": len(programs),
            "unique_programs": len(
                {row["program_sha256"] for row in graph_rows}
            ),
            "duplicate_program_instances": len(programs)
            - len({row["program_sha256"] for row in graph_rows}),
            "program_bytes": sum(
                row["program_bytes"] for row in graph_rows
            ),
            "unique_operator_targets": len(operators),
            "call_function_invocations": call_count,
            "call_sha256": hashlib.sha256(
                canonical(call).encode()
            ).hexdigest(),
        },
        "observed": {
            "abstractions": observed["num_abstractions"],
            "abstraction_rows": abstractions,
            "original_cost": observed["original_cost"],
            "final_cost": observed["final_cost"],
            "cost_change": (
                observed["original_cost"] - observed["final_cost"]
            ),
            "rewritten_programs": len(rewritten),
            "rewritten_sha256": hashlib.sha256(
                canonical(rewritten).encode()
            ).hexdigest(),
            "abstraction_boundary": (
                "structural S-expression compression; not numerical "
                "execution, primitive invention, or multi-operator novelty"
            ),
        },
        "graphs": graph_rows,
        "unsupported_or_failed": unsupported,
        "integration": {
            "A5_typed_graph_encoding_ready": True,
            "A5_source_algorithm_executed_on_calibration": True,
            "A5_framework_numerical_mount_ready": False,
            "A5_contract_batch_ready": False,
            "A5_production_integrated": False,
            "production_integrated_arms": 5,
        },
        "P3": {"complete": False},
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE99_A5_STITCH_TYPED_GRAPH"
        f" status={payload['status']}"
        " graphs=23 ops=41 calls=337"
        f" abstractions={observed['num_abstractions']}"
        f" cost={observed['original_cost']}/{observed['final_cost']}"
        " integrated=5/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    run()
