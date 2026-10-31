#!/usr/bin/env python3
"""Authenticate and materialize fail-closed outcomes for four required arms."""

from __future__ import annotations

import hashlib
import json
import pathlib
from collections import Counter

import torch

from phase63_pareto_motif_calibration import old_repository, workloads


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/REQUIRED_UNSUPPORTED_MATRIX_PROTOCOL_V1.json"
)
RESULT = HERE / "results/phase107_required_unsupported_matrix_audit.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(name: str) -> dict:
    return json.loads((HERE / "results" / name).read_text())


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    for row in protocol["provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"provider mismatch: {row['path']}")

    a1 = load("phase93_a1_ir_compatibility_audit.json")
    babble = load("phase41_babble_source_control.json")
    isamore = load("phase52_isamore_reduced_route_audit.json")
    a7 = load("phase105_a7_enumo_compatibility_audit.json")
    a8_route = load("phase70_eggmind_source_route_audit.json")
    a8_boundary = load(
        "phase71_eggmind_adapted_boundary_conformance.json"
    )
    evidence = {
        "A1": {
            "reason": "INCOMPLETE_IR_SURFACE",
            "facts": {
                "graphs": a1["summary"]["graphs"],
                "direct_graphs": a1["summary"]["whole_graph_direct"],
                "unique_operator_targets": a1["summary"][
                    "unique_operator_targets"
                ],
                "direct_operator_targets": a1["mapping_counts"][
                    "DIRECT_EXACT"
                ],
                "constructor_patterns": a1["summary"][
                    "exact_constructor_pattern_candidates"
                ],
                "production_adapter_ready": a1["summary"][
                    "production_adapter_ready"
                ],
            },
        },
        "A6": {
            "reason": "TOP_LEVEL_ISAMORE_CONTROL_UNAVAILABLE",
            "facts": {
                "babble_core_status": babble["status"],
                "babble_full_official_cli_executed": babble[
                    "full_official_cli_executed"
                ],
                "top_level_status": isamore["status"],
                "core_files_materialized_locally": isamore[
                    "core_files_materialized_locally"
                ],
                "recursive_submodule_identities_observed": isamore[
                    "recursive_submodule_identities_observed"
                ],
                "reduced_route_faithful": isamore[
                    "reduced_route_faithful"
                ],
            },
        },
        "A7": {
            "reason": "NEW_TENSOR_SYNTH_LANGUAGE_REQUIRED",
            "facts": {
                "status": a7["status"],
                "direct_call_matches": a7["framework_surface"][
                    "direct_call_matches"
                ],
                "unsupported_calls": a7["framework_surface"][
                    "unsupported_calls"
                ],
                "missing_domain_component_classes": len(
                    a7["compatibility"][
                        "missing_tensor_domain_components"
                    ]
                ),
                "production_integrated": a7["integration"][
                    "A7_production_integrated"
                ],
            },
        },
        "A8": {
            "reason": (
                "UPSTREAM_EGGMIND_NOT_DISCOVERED_PARTIAL_BOUNDARY_ONLY"
            ),
            "facts": {
                "source_route_status": a8_route["status"],
                "official_repository_matches": a8_route[
                    "official_repository_matches"
                ],
                "partial_boundary_status": a8_boundary["status"],
                "full_control_conformance": a8_boundary["P1"][
                    "full_eggmind_style_control_conformance_passed"
                ],
                "production_integrated": a8_boundary["P1"][
                    "production_integrated"
                ],
                "unimplemented_surfaces": len(
                    a8_boundary["unimplemented_surfaces"]
                ),
            },
        },
    }
    instantiated, unsupported = workloads()
    artifacts = []
    operators = Counter()
    for suite, workload in instantiated:
        family = workload["family"]
        exported = torch.export.export(
            workload["model"],
            workload["args"],
            workload["kwargs"],
            strict=True,
        )
        graph = exported.module().graph
        graph_ops = Counter(
            str(node.target)
            for node in graph.nodes
            if node.op == "call_function"
        )
        operators.update(graph_ops)
        artifacts.append(
            {
                "artifact_id": f"{suite}:{family}",
                "family": family,
                "repository": workload.get(
                    "repository", old_repository(suite, family)
                ),
                "semantic_domain": workload.get(
                    "semantic_domain", family
                ),
                "graph_ir_sha256": hashlib.sha256(
                    str(graph).encode()
                ).hexdigest(),
                "source_sha256": hashlib.sha256(
                    canonical(
                        {
                            "suite": suite,
                            "family": family,
                            "repository": workload.get(
                                "repository",
                                old_repository(suite, family),
                            ),
                            "matrix_protocol_sha256": sha(PROTOCOL),
                        }
                    ).encode()
                ).hexdigest(),
                "shape_seed_sha256": hashlib.sha256(
                    canonical(
                        {
                            "artifact_id": f"{suite}:{family}",
                            "base_seed": 0,
                        }
                    ).encode()
                ).hexdigest(),
                "call_function_invocations": sum(graph_ops.values()),
            }
        )
    outcomes = [
        {
            "arm_id": arm_id,
            "artifact_id": artifact["artifact_id"],
            "status": "REQUIRED_UNSUPPORTED",
            "reason": evidence[arm_id]["reason"],
        }
        for arm_id in protocol["arms"]
        for artifact in artifacts
    ]
    checks = {
        "protocol_prefrozen": protocol["frozen_before_matrix_execution"],
        "provider_hashes_authentic": True,
        "complete_surface_23_41_337": (
            len(artifacts) == 23
            and len(operators) == 41
            and sum(operators.values()) == 337
        ),
        "one_historical_unsupported_explicit": len(unsupported) == 1,
        "four_required_arms": sorted(evidence)
        == ["A1", "A6", "A7", "A8"],
        "A1_reason_authenticated": (
            evidence["A1"]["facts"]["graphs"] == 23
            and evidence["A1"]["facts"]["direct_graphs"] == 4
            and evidence["A1"]["facts"]["constructor_patterns"] == 0
            and evidence["A1"]["facts"]["production_adapter_ready"]
            is False
        ),
        "A6_reason_authenticated": (
            evidence["A6"]["facts"]["babble_core_status"]
            == "BABBLE_SOURCE_CONTROL_STRUCTURAL_PASS"
            and evidence["A6"]["facts"]["babble_full_official_cli_executed"]
            is False
            and evidence["A6"]["facts"]["top_level_status"]
            == "ISAMORE_REDUCED_ROUTE_REJECTED"
            and evidence["A6"]["facts"]["reduced_route_faithful"] is False
        ),
        "A7_reason_authenticated": (
            evidence["A7"]["facts"]["status"]
            == "A7_DIRECT_ADAPTER_REJECTED"
            and evidence["A7"]["facts"]["direct_call_matches"] == 0
            and evidence["A7"]["facts"]["unsupported_calls"] == 337
            and evidence["A7"]["facts"][
                "missing_domain_component_classes"
            ]
            == 8
        ),
        "A8_reason_authenticated": (
            evidence["A8"]["facts"]["source_route_status"]
            == "EGGMIND_UPSTREAM_SOURCE_NOT_DISCOVERED"
            and evidence["A8"]["facts"]["official_repository_matches"] == 0
            and evidence["A8"]["facts"]["partial_boundary_status"]
            == "EGGMIND_ADAPTED_BOUNDARY_CONFORMANCE_PASS"
            and evidence["A8"]["facts"]["full_control_conformance"]
            is False
            and evidence["A8"]["facts"]["production_integrated"] is False
        ),
        "exact_92_required_unsupported_outcomes": (
            len(outcomes) == 92
            and len(
                {
                    (row["arm_id"], row["artifact_id"])
                    for row in outcomes
                }
            )
            == 92
            and all(
                row["status"] == "REQUIRED_UNSUPPORTED"
                and row["reason"]
                == protocol["expected_reasons"][row["arm_id"]]
                for row in outcomes
            )
        ),
        "integration_not_inflated": protocol["claim_boundary"][
            "production_integrated_arms_after_matrix"
        ]
        == 6,
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
            "required-unsupported matrix audit failed: "
            + canonical(
                {
                    "failed": [
                        name for name, passed in checks.items() if not passed
                    ]
                }
            )
        )
    payload = {
        "version": "FOUNDRY_REQUIRED_UNSUPPORTED_MATRIX_AUDIT_V1",
        "status": "REQUIRED_UNSUPPORTED_MATRIX_COMPONENT_PASS",
        "checks": checks,
        "evidence": evidence,
        "artifacts": artifacts,
        "outcomes": outcomes,
        "surface": {
            "graphs": len(artifacts),
            "unique_operator_targets": len(operators),
            "call_function_invocations": sum(operators.values()),
            "unsupported_or_failed_graphs": len(unsupported),
        },
        "integration": {
            "explicit_required_unsupported_arms": 4,
            "explicit_required_unsupported_outcomes": 92,
            "newly_production_integrated_arms": 0,
            "production_integrated_arms": 6,
            "required_arms": 10,
        },
        "P3": {
            "matrix_evidence_ready": True,
            "strict_contract_batch_ready": False,
            "complete": False,
        },
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE107_REQUIRED_UNSUPPORTED_MATRIX"
        f" status={payload['status']}"
        " arms=4 artifacts=23 outcomes=92"
        " integrated=6/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    main()
