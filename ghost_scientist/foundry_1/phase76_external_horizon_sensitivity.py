#!/usr/bin/env python3
"""Stress calibration economics at independently sourced reuse horizons."""

from __future__ import annotations

import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
TRACES = HERE / "external_traces"
OUTPUT = RESULTS / "phase76_external_horizon_sensitivity.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def run() -> None:
    protocol = json.loads(
        (TRACES / "HORIZON_SENSITIVITY_PROTOCOL_V1.json").read_text()
    )
    trace = json.loads(
        (TRACES / "INVOCATION_TRACE_AGGREGATE_V1.json").read_text()
    )
    portfolio = json.loads(
        (RESULTS / "phase64_pareto_portfolio_optimizer.json").read_text()
    )
    candidate = portfolio["selected"]
    fixed = portfolio["fixed"]
    candidate_variable = (
        candidate["definition_cost"]
        + candidate["graph_node_visits"]
        + candidate["edge_checks"]
    )
    fixed_variable = (
        fixed["definition_cost"]
        + fixed["graph_node_visits"]
        + fixed["edge_checks"]
    )
    construction = candidate["shared_construction_cost"]

    def cost(n: int) -> dict:
        candidate_cost = construction + n * candidate_variable
        fixed_cost = n * fixed_variable
        return {
            "N": n,
            "candidate_cost": candidate_cost,
            "fixed_cost": fixed_cost,
            "candidate_minus_fixed": candidate_cost - fixed_cost,
            "candidate_strictly_lower": candidate_cost < fixed_cost,
        }

    rows = {
        name: cost(value) for name, value in protocol["horizons"].items()
    }
    break_even = next(
        n for n in range(1, 100000) if cost(n)["candidate_strictly_lower"]
    )
    primary = rows["external_q25_primary_N_star"]
    checks = {
        "protocol_frozen": protocol["frozen_before_sensitivity_execution"],
        "external_N_star_bound": (
            trace["predeclared_result"]["N_star_external_reference"]
            == primary["N"]
            == 3
        ),
        "candidate_components_recompute": (
            construction + candidate_variable == candidate["total_cost"]
        ),
        "fixed_components_recompute": (
            fixed_variable == fixed["total_cost"]
        ),
        "all_horizons_executed": (
            len(rows) == len(protocol["horizons"]) == 6
        ),
        "primary_condition_passes": primary["candidate_strictly_lower"],
        "positive_integer_break_even": break_even == 1,
        "calibration_only": (
            portfolio["classification"]
            == "CALIBRATION_ONLY_MACHINE_SELECTION"
        ),
    }
    if not all(checks.values()):
        raise RuntimeError("external horizon sensitivity failed")
    payload = {
        "version": "FOUNDRY_EXTERNAL_HORIZON_SENSITIVITY_V1",
        "status": "CALIBRATION_HORIZON_SENSITIVITY_PASS",
        "checks": checks,
        "cost_components": {
            "candidate_shared_construction": construction,
            "candidate_per_horizon_unit": candidate_variable,
            "fixed_per_horizon_unit": fixed_variable,
        },
        "rows": rows,
        "break_even_positive_integer_N": break_even,
        "primary": primary,
        "interpretation": (
            "At the independently sourced lower-quartile horizon N=3, the "
            "calibration-selected portfolio costs 4,862 abstract units versus "
            "7,848 for the fixed portfolio. The result is robust down to N=1 "
            "under this equation, but remains calibration-only and cannot "
            "establish held-out transfer, wall-time savings, or runtime novelty."
        ),
        "P2": {
            "external_horizon_component_ready": True,
            "calibration_economic_stress_passed": True,
            "cross_domain_transfer_justified": False,
            "complete": False,
        },
        "prospective_trial_authorized": False,
        "validation_v6_accessed": False,
    }
    OUTPUT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE76_EXTERNAL_HORIZON_SENSITIVITY"
        f" status={payload['status']}"
        f" N={primary['N']}"
        f" cost={primary['candidate_cost']}/{primary['fixed_cost']}"
        f" break_even={break_even}"
        " P2=false prospective=false"
    )


if __name__ == "__main__":
    run()
