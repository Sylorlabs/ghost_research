#!/usr/bin/env python3
"""Audit whether source-faithful Enumo Boolean admits a direct A7 wrapper."""

from __future__ import annotations

import hashlib
import json
import pathlib
import re
from collections import Counter

import torch

from phase63_pareto_motif_calibration import old_repository, workloads


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE / "arm_adapter_fixtures/A7_ENUMO_COMPATIBILITY_PROTOCOL_V1.json"
)
BOOL_SOURCE = HERE / "external_controls/enumo/upstream_tests/bool.rs"
LANGUAGE_SOURCE = (
    HERE / "external_controls/enumo/source/src/language.rs"
)
RESULT = HERE / "results/phase105_a7_enumo_compatibility_audit.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    for row in protocol["provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"provider mismatch: {row['path']}")
    source = BOOL_SOURCE.read_text()
    language = LANGUAGE_SOURCE.read_text()
    boolean_operators = sorted(
        set(
            re.findall(
                r'^\s*"([^"]+)"\s*=\s*[A-Za-z]+',
                source,
                flags=re.MULTILINE,
            )
        )
    )
    if boolean_operators != protocol["acceptance"][
        "existing_boolean_operator_variants"
    ]:
        raise RuntimeError("Enumo Boolean language surface drift")
    required_domain_methods = {
        name: (f"fn {name}" in source)
        for name in (
            "eval",
            "mk_interval",
            "initialize_vars",
            "mk_var",
            "to_var",
            "validate",
            "is_constant",
            "mk_constant",
        )
    }
    generic_trait_requires_domain = all(
        marker in language
        for marker in (
            "type Constant",
            "fn eval",
            "fn initialize_vars",
            "fn mk_var",
            "fn to_var",
            "fn is_constant",
            "fn mk_constant",
        )
    )
    source_control = json.loads(
        (HERE / "results/phase45_enumo_source_control.json").read_text()
    )
    metamorphic = json.loads(
        (HERE / "results/phase47_enumo_metamorphic_control.json").read_text()
    )
    instantiated, unsupported = workloads()
    graph_rows = []
    operator_counts = Counter()
    for suite, workload in instantiated:
        family = workload["family"]
        exported = torch.export.export(
            workload["model"],
            workload["args"],
            workload["kwargs"],
            strict=True,
        )
        graph = exported.module().graph
        counts = Counter(
            str(node.target)
            for node in graph.nodes
            if node.op == "call_function"
        )
        operator_counts.update(counts)
        graph_rows.append(
            {
                "artifact_id": f"{suite}:{family}",
                "family": family,
                "repository": workload.get(
                    "repository", old_repository(suite, family)
                ),
                "graph_sha256": hashlib.sha256(
                    str(graph).encode()
                ).hexdigest(),
                "call_function_invocations": sum(counts.values()),
                "operator_targets": sorted(counts),
            }
        )
    direct_matches = {
        target: count
        for target, count in operator_counts.items()
        if target in boolean_operators
    }
    unsupported_counts = {
        target: count
        for target, count in sorted(operator_counts.items())
        if target not in boolean_operators
    }
    missing_tensor_domain_components = [
        "typed framework operator language variants",
        "tensor concrete-value or characteristic-vector evaluator",
        "shape dtype layout and alias semantics",
        "tensor variable and constant initialization policy",
        "partial undefined and exceptional operator semantics",
        "sound tensor rewrite validation relation",
        "typed graph workload enumeration recipe",
        "tensor rule cost filter and scheduling policy",
    ]
    direct_adapter_possible = (
        sum(direct_matches.values())
        == protocol["acceptance"][
            "direct_operator_target_matches_required_for_adapter"
        ]
        and not missing_tensor_domain_components
    )
    checks = {
        "protocol_prefrozen": protocol[
            "frozen_before_framework_graph_inspection"
        ],
        "provider_hashes_authentic": True,
        "source_control_conformance_preserved": (
            source_control["status"]
            == "ENUMO_SOURCE_CONTROL_CONFORMANCE_PASS"
            and source_control["conformance_passed"] is True
            and source_control["full_official_crate_executed"] is False
        ),
        "metamorphic_failure_preserved": (
            metamorphic["status"] == "ENUMO_METAMORPHIC_CONTROL_FAIL"
            and metamorphic["checks"][
                "entire_sorted_rule_set_invariant"
            ]
            is False
        ),
        "boolean_language_exactly_5_operators": len(boolean_operators) == 5,
        "boolean_domain_methods_explicit": all(
            required_domain_methods.values()
        ),
        "generic_engine_requires_domain_implementation": (
            generic_trait_requires_domain
        ),
        "complete_framework_surface_23_41_337": (
            len(graph_rows) == 23
            and len(operator_counts) == 41
            and sum(operator_counts.values()) == 337
        ),
        "one_unsupported_graph_explicit": len(unsupported) == 1,
        "zero_direct_operator_matches": (
            len(direct_matches) == 0
            and sum(direct_matches.values()) == 0
        ),
        "all_337_calls_directly_unsupported": sum(
            unsupported_counts.values()
        )
        == 337,
        "new_tensor_domain_required": len(
            missing_tensor_domain_components
        )
        == 8,
        "direct_adapter_rejected": direct_adapter_possible is False,
        "integration_not_inflated": protocol["claim_boundary"][
            "production_integrated_arms_after_rejected_direct_adapter"
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
            "A7 Enumo compatibility audit failed: "
            + canonical(
                {
                    "failed": [
                        name for name, passed in checks.items() if not passed
                    ]
                }
            )
        )
    payload = {
        "version": "FOUNDRY_A7_ENUMO_COMPATIBILITY_AUDIT_V1",
        "status": "A7_DIRECT_ADAPTER_REJECTED",
        "classification": (
            "REQUIRED_UNSUPPORTED_WITHOUT_NEW_TENSOR_SYNTH_LANGUAGE"
        ),
        "checks": checks,
        "source_control": {
            "classification": source_control["classification"],
            "upstream_algorithm_source_executed": source_control[
                "upstream_algorithm_source_executed"
            ],
            "official_boolean_test_logic_executed": source_control[
                "official_boolean_test_logic_executed"
            ],
            "full_official_crate_executed": source_control[
                "full_official_crate_executed"
            ],
            "learned_boolean_rules": source_control["observed"][
                "total_rules"
            ],
            "boolean_operator_variants": boolean_operators,
            "required_domain_methods": required_domain_methods,
        },
        "metamorphic_boundary": {
            "status": metamorphic["status"],
            "workload_counts_invariant": metamorphic["checks"][
                "workload_counts_invariant"
            ],
            "entire_rule_set_invariant": metamorphic["checks"][
                "entire_sorted_rule_set_invariant"
            ],
            "baseline_total_rules": source_control["observed"][
                "total_rules"
            ],
            "transformed_total_rules": metamorphic["observed"][
                "total_rules"
            ],
        },
        "framework_surface": {
            "graphs": len(graph_rows),
            "unique_operator_targets": len(operator_counts),
            "call_function_invocations": sum(operator_counts.values()),
            "direct_operator_target_matches": direct_matches,
            "direct_call_matches": sum(direct_matches.values()),
            "unsupported_operator_counts": unsupported_counts,
            "unsupported_calls": sum(unsupported_counts.values()),
            "graphs_rows": graph_rows,
            "unsupported_or_failed": unsupported,
        },
        "compatibility": {
            "direct_adapter_possible": False,
            "missing_tensor_domain_components": (
                missing_tensor_domain_components
            ),
            "faithful_future_route": (
                "A separately predeclared tensor SynthLanguage and sound "
                "domain semantics would be new research construction, not a "
                "direct wrapper; it must be evaluated as such before A7 can "
                "advance."
            ),
        },
        "integration": {
            "A7_compatibility_audited": True,
            "A7_direct_adapter_supported": False,
            "A7_production_integrated": False,
            "production_integrated_arms": 6,
            "required_arms": 10,
        },
        "P3": {"complete": False},
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE105_A7_ENUMO_COMPATIBILITY"
        f" status={payload['status']}"
        " graphs=23 ops=41 calls=337 direct=0 unsupported=337"
        " integrated=6/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    main()
