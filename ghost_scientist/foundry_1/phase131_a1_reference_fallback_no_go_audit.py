#!/usr/bin/env python3
"""Prove that an opaque framework fallback is outside frozen A1 semantics."""

from __future__ import annotations

import ast
import hashlib
import importlib.util
import json
import pathlib
import sys
import tempfile


HERE = pathlib.Path(__file__).resolve().parent
CORE = HERE / "../operator_v5/ghost_operator_core_v5.py"
CANDIDATE = HERE / "../operator_v5/ghost_operator_candidate_v5.py"
PROTOCOL = HERE / "arm_adapter_fixtures/A1_IR_COMPATIBILITY_PROTOCOL_V1.json"
PRIOR = HERE / "results/phase93_a1_ir_compatibility_audit.json"
ARTIFACT = (
    HERE
    / "../operator_v5/results/development_corpus/artifacts/dev_000.json"
)
RESULT = HERE / "results/phase131_a1_reference_fallback_no_go_audit.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def module(path: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    loaded = importlib.util.module_from_spec(spec)
    sys.modules[name] = loaded
    spec.loader.exec_module(loaded)
    return loaded


def function_calls(source: str, function_name: str) -> set[str]:
    tree = ast.parse(source)
    function = next(
        node
        for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == function_name
    )
    return {
        node.func.id
        for node in ast.walk(function)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
    }


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    prior = json.loads(PRIOR.read_text())
    for row in protocol["provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"A1 provider hash mismatch: {row['path']}")
    if not (
        prior["status"]
        == "A1_DIRECT_ADAPTER_REJECTED_INCOMPLETE_IR_SURFACE"
        and prior["summary"]["graphs"] == 23
        and prior["summary"]["whole_graph_direct"] == 4
        and prior["summary"]["exact_constructor_pattern_candidates"] == 0
    ):
        raise RuntimeError("prior A1 compatibility boundary changed")

    core_source = CORE.read_text()
    candidate_source = CANDIDATE.read_text()
    core_calls = function_calls(core_source, "load_artifact")
    candidate_calls = function_calls(candidate_source, "reference_plan")
    construct_calls = function_calls(candidate_source, "construct")
    if not (
        "infer_runtime_program" in core_calls
        and candidate_calls == {"plan"}
        and "enumerate_plans" in construct_calls
    ):
        raise RuntimeError("A1 reference-path call graph changed")

    core = module(CORE, "foundry_phase131_core")
    candidate = module(CANDIDATE, "foundry_phase131_candidate")
    payload = json.loads(ARTIFACT.read_text())
    reference = candidate.reference_plan(payload)
    if reference["program"] != payload["reference_program"]:
        raise RuntimeError("candidate reference plan is not identity transport")

    mutated = json.loads(canonical(payload))
    target = next(
        node
        for node in mutated["reference_program"]["nodes"]
        if node["op"] not in {"input", "parameter"}
    )
    original_op = target["op"]
    target["op"] = "opaque_framework_call"
    target["attrs"] = {}
    with tempfile.TemporaryDirectory(prefix="foundry-a1-no-go-") as tmp:
        path = pathlib.Path(tmp) / "opaque.json"
        path.write_text(canonical(mutated) + "\n")
        try:
            core.load_artifact(path)
        except core.ContractError as exc:
            rejection = str(exc)
        else:
            raise RuntimeError("A1 accepted an opaque framework operation")
    if "unsupported runtime op: opaque_framework_call" not in rejection:
        raise RuntimeError("unexpected A1 opaque-op rejection")

    checks = {
        "provider_hashes_authentic": True,
        "load_artifact_typechecks_reference_program": True,
        "candidate_reference_plan_is_identity_transport": True,
        "construct_enumerates_only_operator_v5_plans": True,
        "opaque_framework_call_rejected": True,
        "all_23_graphs_exactly_lowerable": False,
        "nonreference_constructor_on_calibration": False,
        "opaque_fallback_can_promote_A1": False,
        "validation_v6_unread": True,
    }
    payload_out = {
        "version": "FOUNDRY_A1_REFERENCE_FALLBACK_NO_GO_AUDIT_V1",
        "status": "A1_OPAQUE_REFERENCE_FALLBACK_FORMALLY_REJECTED",
        "checks": checks,
        "call_graph": {
            "core_load_artifact_calls": sorted(core_calls),
            "candidate_reference_plan_calls": sorted(candidate_calls),
            "candidate_construct_calls": sorted(construct_calls),
        },
        "hostile_probe": {
            "source_artifact": str(ARTIFACT.relative_to(HERE)),
            "replaced_runtime_op": original_op,
            "hostile_runtime_op": "opaque_framework_call",
            "rejection": rejection,
        },
        "surface": {
            "graphs": 23,
            "whole_graph_direct": 4,
            "unsupported_targets": prior["mapping_counts"]["UNSUPPORTED"],
            "unsupported_invocations": prior["invocation_counts"]["UNSUPPORTED"],
            "constructor_pattern_candidates": 0,
        },
        "decision": {
            "A1_production_integrated": False,
            "production_integrated_arms": 6,
            "required_arms": 10,
            "allowed_future_routes": [
                "extend A1 only as a newly named arm with a newly frozen vocabulary",
                "leave frozen A1 fail-closed",
            ],
            "forbidden_route": (
                "wrap arbitrary framework execution as the frozen A1 reference plan"
            ),
            "next_reachable_arm": "A6",
            "fallback_research_route_if_transport_stays_closed": (
                "prefreeze and build a separately named Enumo tensor-domain arm; "
                "do not relabel the Boolean A7 control"
            ),
        },
        "P3_complete": True,
        "P1_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
        "claim_boundary": (
            "This is a semantic no-go result for a proposed adapter shortcut, "
            "not an impossibility theorem for every future language. Frozen A1 "
            "cannot execute an opaque framework call because even its reference "
            "plan is typechecked as strict Operator-v5 IR."
        ),
    }
    if not all(checks.values()):
        false_checks = [key for key, value in checks.items() if not value]
        if false_checks != [
            "all_23_graphs_exactly_lowerable",
            "nonreference_constructor_on_calibration",
            "opaque_fallback_can_promote_A1",
        ]:
            raise RuntimeError(f"unexpected A1 no-go checks: {false_checks}")
    RESULT.write_text(canonical(payload_out) + "\n")
    print(
        "FOUNDRY_PHASE131_A1_REFERENCE_FALLBACK_NO_GO"
        " status=FORMALLY_REJECTED hostile=1/1"
        " direct_graphs=4/23 patterns=0 integrated=6/10"
        " validation_v6=false"
    )


if __name__ == "__main__":
    main()
