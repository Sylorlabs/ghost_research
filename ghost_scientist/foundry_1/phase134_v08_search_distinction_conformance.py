#!/usr/bin/env python3
"""Independently audit and meter the pre-frozen V08 search endpoint."""

from __future__ import annotations

import hashlib
import json
import pathlib
import sys

from independent_v08_search_distinction import (
    REQUIRED_FIELDS,
    hostile_selftest,
    synthetic_document,
    verify_trial,
)
from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
GHOST = HERE.parent
PROTOCOL = HERE / "PARETO_V08_SEARCH_DISTINCTION_PROTOCOL_V1.json"
FREEZE = HERE / "results/pareto_v08_search_distinction_v1_freeze.json"
WORKER = HERE / "results/phase134_v08_search_distinction_worker.json"
RESULT = HERE / "results/phase134_v08_search_distinction_conformance.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def worker() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    foundry_0 = (GHOST / "foundry_0/FALSIFICATION_PROTOCOL.md").read_text()
    prospective = json.loads(
        (HERE / "PARETO_PROSPECTIVE_PROTOCOL_V1.json").read_text()
    )
    candidate = json.loads(
        (HERE / "results/forged_pareto_tools.json").read_text()
    )
    grammar = json.loads(
        (HERE / "results/phase55_diversity_tool_forge.json").read_text()
    )
    conformance = json.loads(
        (HERE / "results/phase65_independent_pareto_conformance.json").read_text()
    )
    native = json.loads(
        (HERE / "results/phase66_pareto_native_dedup.json").read_text()
    )
    for row in protocol["frozen_inputs"]:
        if sha(GHOST / row["path"]) != row["sha256"]:
            raise RuntimeError(f"frozen input mismatch: {row['path']}")
    tool_digests = {tool["tool_id"] for tool in candidate["tools"]}
    if len(tool_digests) != 4:
        raise RuntimeError("candidate tool identity changed")
    synthetic = verify_trial(
        synthetic_document(sorted(tool_digests)[0]),
        candidate_tool_digests=tool_digests,
        bootstrap_resamples=protocol["primary_endpoint"][
            "paired_bootstrap"
        ]["resamples"],
        bootstrap_seed=protocol["primary_endpoint"]["paired_bootstrap"]["seed"],
    )
    hostile = hostile_selftest(sorted(tool_digests)[0])
    checks = {
        "freeze_matches_protocol": (
            freeze["protocol_sha256"] == sha(PROTOCOL)
            and freeze["frozen_inputs"] == protocol["frozen_inputs"]
            and freeze["frozen_before_heldout_execution"] is True
        ),
        "foundry_0_V08_exactly_present": (
            "| V08 | All accepted tools pass native-compiler deduplication "
            "or disclose a measured search-cost distinction. |"
            in foundry_0
        ),
        "parent_prospective_V08_present": (
            "V08 native dedup or disclosed measured search distinction"
            in prospective["hard_validity_gates"]
        ),
        "candidate_identity_unchanged": (
            len(candidate["tools"]) == 4
            and candidate["selected_metrics"]["tools"] == 4
            and sha(HERE / "results/forged_pareto_tools.json")
            == protocol["frozen_inputs"][3]["sha256"]
        ),
        "machine_grammar_not_reimplemented": (
            grammar["autonomy_boundary"]["llm_calls"] == 0
            and grammar["autonomy_boundary"]["supplied_tool_forms"] == 0
            and grammar["autonomy_boundary"][
                "targets_chosen_by_machine"
            ]
            is True
            and grammar["autonomy_boundary"][
                "argument_grammar_constructed_by_machine"
            ]
            is True
        ),
        "calibration_candidate_beats_fixed_but_not_heldout": (
            conformance["classification"]
            == "CALIBRATION_ONLY_INDEPENDENT_CONFORMANCE"
            and conformance["candidate"]["unique_nodes"] == 53
            and conformance["fixed"]["unique_nodes"] == 51
            and conformance["candidate"]["total_cost"] == 2234
            and conformance["fixed"]["total_cost"] == 2616
            and conformance["access_audit"]["forbidden_open_count"] == 0
        ),
        "native_duplicate_fact_preserved": (
            native["summary"]["tools"] == 4
            and native["summary"]["stock_decomposition_duplicates"] == 4
            and native["summary"]["runtime_inventions_admitted"] == 0
            and native["summary"]["semantic_search_candidates_retained"] == 4
        ),
        "independent_schema_exact": (
            set(protocol["required_raw_receipt_fields"]) == REQUIRED_FIELDS
            and len(REQUIRED_FIELDS) == 22
        ),
        "synthetic_positive_control_passes": (
            synthetic["passed"] is True
            and synthetic["delta_search"] >= 0.05
            and synthetic["bootstrap_lower_95"] > 0
            and synthetic["artifacts"] == 4
            and synthetic["receipts"] == 12
        ),
        "fifteen_hostile_ledgers_rejected": (
            hostile["hostile_cases"] == 15
            and hostile["rejected_cases"] == 15
            and hostile["all_rejected"] is True
        ),
        "no_threshold_weakening": (
            protocol["primary_endpoint"]["point_estimate_minimum"] == 0.05
            and protocol["primary_endpoint"]["paired_bootstrap"][
                "lower_bound_must_be_strictly_positive"
            ]
            is True
            and protocol["measurement_schedule"]["pairing_unit"] == "artifact"
            and protocol["measurement_schedule"]["bootstrap_sample_size"] == 4
        ),
        "total_cost_and_fixed_reporting_preserved": (
            protocol["hard_acceptance"][
                "fixed_and_stock_total_cost_results_still_reported"
            ]
            is True
            and protocol["hard_acceptance"][
                "complete_total_cost_accounting_unchanged"
            ]
            is True
        ),
        "preflight_does_not_claim_outcome_or_authorization": (
            protocol["preflight_effect"]["V08_measurement_passed_before_heldout"]
            is False
            and protocol["preflight_effect"][
                "prospective_trial_authorized_by_this_protocol"
            ]
            is False
            and protocol["claim_boundary"]["heldout_result_claimed"] is False
            and protocol["claim_boundary"]["V08_pass_claimed"] is False
            and protocol["claim_boundary"]["runtime_novelty_claimed"] is False
        ),
        "validation_v6_unread": (
            protocol["claim_boundary"][
                "validation_v6_source_runtime_graph_or_outcome_accessed"
            ]
            is False
        ),
    }
    if not all(checks.values()):
        raise RuntimeError(
            "V08 conformance failed: "
            + ",".join(sorted(name for name, passed in checks.items() if not passed))
        )
    payload = {
        "version": "FOUNDRY_V08_SEARCH_DISTINCTION_WORKER_V1",
        "checks": checks,
        "candidate_tool_digests": sorted(tool_digests),
        "synthetic_positive_control": synthetic,
        "hostile_selftest": hostile,
        "terminal_native_dedup_stop": "PENDING_PREFROZEN_V08_MEASUREMENT",
        "V08_measurement_passed": False,
        "runtime_novelty_claimed": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    WORKER.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE134_V08_WORKER"
        f" checks={sum(checks.values())}/{len(checks)}"
        f" hostile={hostile['rejected_cases']}/{hostile['hostile_cases']}"
        " outcome=pending prospective=false"
    )


def main() -> None:
    if "--worker" in sys.argv:
        worker()
        return
    python = pathlib.Path(sys.executable).resolve()
    meter_test = selftest(str(python), GHOST.parent)
    limits = {
        "wall_limit_seconds": 30,
        "cpu_limit_seconds": 20,
        "rss_limit_kib": 512000,
    }
    receipt = run_metered_tree(
        [str(python), str(pathlib.Path(__file__).resolve()), "--worker"],
        cwd=HERE,
        environment={"PYTHONHASHSEED": "0"},
        **limits,
    )
    natural = (
        receipt["returncode"] == 0
        and receipt["termination"] == "natural"
        and receipt["process_group_reaped"] is True
        and "FOUNDRY_PHASE134_V08_WORKER" in receipt["stdout_text"]
    )
    worker_result = (
        json.loads(WORKER.read_text())
        if natural and WORKER.exists()
        else {}
    )
    checks = {
        "meter_hostile_selftest": meter_test["pass"],
        "worker_natural_and_reaped": natural,
        "worker_cpu_rss_wall_accounted": (
            natural
            and receipt["observed_process_count"] >= 1
            and receipt["peak_group_rss_kib"] > 0
            and receipt["rusage_user_cpu_ns"]
            + receipt["rusage_system_cpu_ns"]
            > 0
        ),
        "all_worker_checks_pass": (
            isinstance(worker_result.get("checks"), dict)
            and all(worker_result["checks"].values())
        ),
        "hostile_ledgers_rejected": (
            worker_result.get("hostile_selftest", {}).get("all_rejected") is True
        ),
        "V08_still_pending": (
            worker_result.get("V08_measurement_passed") is False
            and worker_result.get("terminal_native_dedup_stop")
            == "PENDING_PREFROZEN_V08_MEASUREMENT"
        ),
        "runtime_novelty_not_claimed": (
            worker_result.get("runtime_novelty_claimed") is False
        ),
        "validation_v6_unread": (
            worker_result.get("validation_v6_accessed") is False
        ),
        "prospective_unauthorized": (
            worker_result.get("prospective_trial_authorized") is False
        ),
    }
    status = (
        "V08_SEARCH_DISTINCTION_PREFLIGHT_CONFORMANCE_PASS"
        if all(checks.values())
        else "V08_SEARCH_DISTINCTION_PREFLIGHT_CONFORMANCE_FAIL"
    )
    payload = {
        "version": "FOUNDRY_V08_SEARCH_DISTINCTION_CONFORMANCE_V1",
        "status": status,
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "independent_verifier_sha256": sha(
            HERE / "independent_v08_search_distinction.py"
        ),
        "limits": limits,
        "meter_selftest": meter_test,
        "receipt": receipt,
        "worker": worker_result,
        "checks": checks,
        "preflight_effect": {
            "duplicate_grammar_phase_required": False,
            "native_duplicate_fact_preserved": True,
            "terminal_native_dedup_stop": "PENDING_PREFROZEN_V08_MEASUREMENT",
            "V08_measurement_passed": False,
            "P1_advanced": False,
            "production_integrated_arms": 6,
            "validation_v6_accessed": False,
            "prospective_trial_authorized": False,
        },
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE134_V08_SEARCH_CONFORMANCE"
        f" status={status}"
        f" hostile={worker_result.get('hostile_selftest', {}).get('rejected_cases', 0)}/15"
        " V08=pending P1=false integrated=6/10 prospective=false"
    )


if __name__ == "__main__":
    main()
