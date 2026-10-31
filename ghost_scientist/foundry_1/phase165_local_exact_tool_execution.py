#!/usr/bin/env python3
"""Execute Phase165 real-value replay, causality, and native dedup."""

from __future__ import annotations

import copy
import hashlib
import json
import pathlib
import sys

from independent_local_exact_tool_execution_v1 import (
    IndependentExactToolExecutionReject,
    expected_execution_ledger,
    verify_ledger as independent_verify,
)
from local_exact_tool_execution_core_v1 import (
    ExactToolExecutionReject,
    canonical,
    digest,
    prime_verifier_expected,
    run_execution,
    stable_ledger,
    verify_ledger,
)
from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "arm_adapter_fixtures/LOCAL_EXACT_TOOL_EXECUTION_PROTOCOL_V1.json"
FREEZE = HERE / "results/local_exact_tool_execution_v1_freeze.json"
WORKER = HERE / "results/phase165_local_exact_tool_execution_worker.json"
RESULT = HERE / "results/phase165_local_exact_tool_execution.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def worker() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    primary = run_execution()
    prime_verifier_expected(primary)
    independent = expected_execution_ledger()
    verify_ledger(primary, protocol)
    independent_verify(primary, protocol)
    independent_summary = independent["summary"]
    if not (
        independent_summary["exact_matches_executed"]
        == primary["summary"]["execution_rows"]
        == 17
        and independent_summary["unique_bodies_executed"]
        == primary["summary"]["unique_bodies"]
        == 3
        and independent_summary["declared_outputs_checked"]
        == primary["summary"]["declared_outputs_checked"]
        == 17
        and independent_summary["maximum_abs_error"] <= 1e-6
    ):
        raise RuntimeError("independent exact-tool execution evidence disagrees")
    hostile = []

    def case(name: str, mutate) -> None:
        altered = copy.deepcopy(primary)
        mutate(altered)
        rejected = []
        for verifier, error in (
            (verify_ledger, ExactToolExecutionReject),
            (independent_verify, IndependentExactToolExecutionReject),
        ):
            try:
                verifier(altered, protocol)
            except (error, KeyError, TypeError, ValueError, json.JSONDecodeError):
                rejected.append(True)
            else:
                rejected.append(False)
        hostile.append(
            {"case": name, "primary_rejected": rejected[0], "independent_rejected": rejected[1]}
        )

    case("source_match_mutation", lambda value: value.update(source_phase164_sha256="0" * 64))
    case(
        "external_input_order_mutation",
        lambda value: value["execution_rows"][0]["external_input_node_names"].reverse(),
    )
    case(
        "candidate_output_mutation",
        lambda value: value["execution_rows"][0]["candidate_output_errors"].__setitem__(0, 1.0),
    )
    case(
        "independent_output_mutation",
        lambda value: value["execution_rows"][0]["stock_output_errors"].__setitem__(0, 1.0),
    )
    case(
        "declared_output_omission",
        lambda value: value["execution_rows"][0].update(declared_outputs=0),
    )
    case(
        "floating_error_inflation",
        lambda value: value["execution_rows"][0]["candidate_output_errors"].__setitem__(0, 1e-5),
    )
    case(
        "nonfloating_mismatch",
        lambda value: value["execution_rows"][0]["stock_output_errors"].__setitem__(0, float("inf")),
    )
    case(
        "causal_total_mutation",
        lambda value: value["causal"].update(matches_after_remove_all=1),
    )
    case(
        "per_body_causal_loss_mutation",
        lambda value: value["causal"]["per_body_losses"].update(
            {next(iter(value["causal"]["per_body_losses"])): 0}
        ),
    )
    case(
        "candidate_compiler_digest_mutation",
        lambda value: value["native_rows"][0]["candidate"].update(code_sha256="0" * 64),
    )
    case(
        "stock_compiler_digest_mutation",
        lambda value: value["native_rows"][0]["stock"].update(code_sha256="0" * 64),
    )
    case(
        "compile_failure_hidden",
        lambda value: value["native_rows"][0]["candidate"].update(error="hidden"),
    )
    case(
        "whole_graph_replacement_claim_inflation",
        lambda value: value["claims"].update(whole_graph_replacement_demonstrated=True),
    )
    case(
        "P6_or_prospective_claim_inflation",
        lambda value: value["claims"].update(P6_advanced=True, prospective_trial_authorized=True),
    )
    summary = primary["summary"]
    execution_pass = (
        summary["execution_rows"] == summary["source_matches"] == 17
        and summary["candidate_exact_rows"] == 17
        and summary["stock_exact_rows"] == 17
        and summary["causal_matches_after_remove_all"] == 0
    )
    payload = {
        "version": "FOUNDRY_LOCAL_EXACT_TOOL_EXECUTION_WORKER_V1",
        "ledger": primary,
        "stable_ledger_sha256": digest(stable_ledger(primary)),
        "independent_execution_ledger_sha256": digest(independent),
        "independent_execution_summary": independent_summary,
        "hostile_rejections": hostile,
        "summary": {
            **summary,
            "independent_implementations": 2,
            "hostile_cases": len(hostile),
            "hostile_rejected_twice": sum(
                row["primary_rejected"] and row["independent_rejected"] for row in hostile
            ),
        },
        "classification": (
            "LOCAL_EXACT_TOOL_EXECUTION_RUNTIME_INVENTION"
            if execution_pass and summary["runtime_inventions_admitted"] > 0
            else "LOCAL_EXACT_TOOL_EXECUTION_VALID_STOCK_DUPLICATE"
            if execution_pass
            else "LOCAL_EXACT_TOOL_EXECUTION_INFRASTRUCTURE_FAILURE"
        ),
        "validation_v6_or_v7_accessed": False,
        "prospective_trial_authorized": False,
    }
    WORKER.write_text(json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n")
    print(
        "FOUNDRY_PHASE165_WORKER"
        f" classification={payload['classification']}"
        f" replay={summary['candidate_exact_rows']}/{summary['source_matches']}"
        f" compiles={summary['candidate_compile_successes']}/{summary['stock_compile_successes']}"
        f" duplicates={summary['normalized_inductor_duplicates']}"
        f" inventions={summary['runtime_inventions_admitted']}"
    )


def main() -> None:
    if len(sys.argv) == 2 and sys.argv[1] == "--worker":
        worker()
        return
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    if not (
        freeze["status"]
        == "FROZEN_BEFORE_TOOL_EXECUTION_CAUSALITY_OR_NATIVE_COMPILATION"
        and freeze["protocol_sha256"] == sha(PROTOCOL)
        and all(sha(HERE / row["path"]) == row["sha256"] for row in protocol["provider_records"])
    ):
        raise RuntimeError("exact-tool execution freeze mismatch")
    limits = protocol["resource_limits"]
    receipt = run_metered_tree(
        [sys.executable, str(pathlib.Path(__file__).resolve()), "--worker"],
        cwd=HERE,
        wall_limit_seconds=limits["wall_seconds"],
        cpu_limit_seconds=limits["cpu_seconds"],
        rss_limit_kib=limits["rss_kib"],
        environment={
            "PYTHONWARNINGS": "ignore",
            "TORCHINDUCTOR_COMPILE_THREADS": "1",
            "MAX_JOBS": "1",
        },
    )
    if receipt["returncode"] != 0:
        failure = HERE / "results/phase165_local_exact_tool_execution_failed_worker_receipt.json"
        failure.write_text(json.dumps(receipt, sort_keys=True, separators=(",", ":")) + "\n")
        raise RuntimeError("exact-tool execution worker failed: " + receipt["stderr_text"])
    observed = json.loads(WORKER.read_text())
    summary = observed["summary"]
    checks = {
        "protocol_frozen_before_execution_or_native_outcomes": True,
        "two_independent_implementations_agree": (
            summary["independent_implementations"] == 2
            and observed["independent_execution_summary"][
                "exact_matches_executed"
            ]
            == summary["execution_rows"]
            and observed["independent_execution_summary"][
                "unique_bodies_executed"
            ]
            == summary["unique_bodies"]
            and observed["independent_execution_summary"][
                "declared_outputs_checked"
            ]
            == summary["declared_outputs_checked"]
            and observed["independent_execution_summary"]["maximum_abs_error"]
            <= 1e-6
        ),
        "fourteen_hostile_cases_rejected_twice": (
            summary["hostile_cases"] == summary["hostile_rejected_twice"] == 14
        ),
        "all_real_value_replays_exact": (
            summary["candidate_exact_rows"] == summary["stock_exact_rows"]
            == summary["execution_rows"] == summary["source_matches"] == 17
        ),
        "all_declared_outputs_checked": summary["declared_outputs_checked"] == 17,
        "causal_removal_exact": summary["causal_matches_after_remove_all"] == 0,
        "all_unique_bodies_compiled_twice": (
            summary["candidate_compile_successes"]
            == summary["stock_compile_successes"]
            == summary["native_compile_rows"]
            == summary["unique_bodies"]
            == 3
        ),
        "native_classification_exact": (
            summary["normalized_inductor_duplicates"]
            + summary["runtime_inventions_admitted"]
            == summary["native_compile_rows"]
        ),
        "claim_boundary_preserved": (
            observed["ledger"]["claims"]["whole_graph_replacement_demonstrated"] is False
            and observed["ledger"]["claims"]["lower_total_cost_demonstrated"] is False
            and observed["ledger"]["claims"]["P6_advanced"] is False
            and observed["prospective_trial_authorized"] is False
        ),
        "metered_worker_passed": (
            receipt["returncode"] == 0
            and receipt["termination"] == "natural"
            and receipt["process_group_reaped"] is True
        ),
    }
    if not all(checks.values()):
        raise RuntimeError("exact-tool execution result failed")
    result = {
        "version": "FOUNDRY_LOCAL_EXACT_TOOL_EXECUTION_RESULT_V1",
        "status": observed["classification"],
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "checks": checks,
        "operationally_valid": True,
        "observed": observed,
        "receipt": receipt,
        "decision": {
            "concrete_exact_tool_reuse_executed": True,
            "whole_graph_replacement_demonstrated": False,
            "lower_total_cost_demonstrated": False,
            "new_operation_semantics": False,
            "native_dedup_executed": True,
            "runtime_primitive_invented": summary["runtime_inventions_admitted"] > 0,
            "P2_advanced": False,
            "P6_advanced": False,
            "prospective_trial_authorized": False,
            "next_route": (
                "do not claim runtime invention: the three executable predicted "
                "tools normalize to stock compiler duplicates; the remaining "
                "scientific route is a prefrozen total-cost or newly-reachable "
                "test against the strong fixed portfolio"
            ),
        },
        "claim_boundary": protocol["claim_boundary"],
    }
    RESULT.write_text(json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n")
    print(
        "FOUNDRY_PHASE165"
        f" status={result['status']}"
        f" replay={summary['candidate_exact_rows']}/{summary['source_matches']}"
        f" unique={summary['unique_bodies']}"
        f" duplicates={summary['normalized_inductor_duplicates']}"
        f" inventions={summary['runtime_inventions_admitted']}"
        " lower_cost=false P6=false prospective=false"
    )


if __name__ == "__main__":
    main()
