#!/usr/bin/env python3
"""Independent stdlib-only recomputation of the v5.1 prospective verdict."""

from __future__ import annotations

import hashlib
import json
import math
import pathlib
from collections import defaultdict


HERE = pathlib.Path(__file__).resolve().parent
TRIAL = HERE / "results/heldout_trial"
CORPUS = HERE / "results/heldout_corpus"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def geometric(values: list[float]) -> float:
    return math.exp(sum(math.log(value) for value in values) / len(values))


def main() -> None:
    verdict = json.loads((TRIAL / "verdict.json").read_text())
    summary = json.loads((TRIAL / "control_summary.json").read_text())
    containment = json.loads((TRIAL / "containment.json").read_text())
    rows = [json.loads(line) for line in (TRIAL / "outcomes.jsonl").read_text().splitlines()]
    candidates = {
        row["opaque_id"]: row
        for row in (
            json.loads(line)
            for line in (TRIAL / "candidate_receipts.jsonl").read_text().splitlines()
        )
    }
    provenance = {
        row["opaque_id"]: row
        for row in (
            json.loads(line)
            for line in (CORPUS / "provenance.private.jsonl").read_text().splitlines()
        )
    }
    by_artifact: dict[str, dict[int, dict]] = defaultdict(dict)
    for row in rows:
        key = int(row["plan_index"])
        if key in by_artifact[row["opaque_id"]]:
            raise RuntimeError("duplicate outcome")
        by_artifact[row["opaque_id"]][key] = row
    if len(by_artifact) != 24 or len(rows) != 48:
        raise RuntimeError("outcome count mismatch")

    objective_fields = (
        "setup_compile_us",
        "latency_us",
        "amortized_total_us",
        "peak_rss_kb",
    )
    recomputed_scores: dict[str, dict[int, float]] = defaultdict(dict)
    for opaque_id, plans in by_artifact.items():
        valid = [
            row
            for row in plans.values()
            if row["measurement_status"] == "MEASURED" and row["numerically_valid"]
        ]
        if len(valid) != len(plans):
            raise RuntimeError(f"invalid outcome in {opaque_id}")
        minima = {
            field: min(max(float(row["objectives"][field]), 1.0e-9) for row in valid)
            for field in objective_fields
        }
        for index, row in plans.items():
            score = geometric(
                [
                    max(float(row["objectives"][field]), 1.0e-9) / minima[field]
                    for field in objective_fields
                ]
            )
            if abs(score - float(row["score"])) > 1.0e-12:
                raise RuntimeError(f"stored score drift in {opaque_id}/{index}")
            recomputed_scores[opaque_id][index] = score

    receipt_by_id = {item["opaque_id"]: item for item in summary["receipts"]}
    if set(receipt_by_id) != set(candidates) or len(candidates) != 24:
        raise RuntimeError("candidate/control receipt coverage mismatch")
    method_values: dict[str, list[float]] = defaultdict(list)
    selected: dict[str, int] = {}
    for opaque_id, candidate in candidates.items():
        index = int(candidate["plan_index"])
        selected[opaque_id] = index
        choices = receipt_by_id[opaque_id]["choices"]
        if int(choices["candidate"]) != index:
            raise RuntimeError("contained candidate/control selection drift")
        for method, plan_index in choices.items():
            method_values[method].append(
                recomputed_scores[opaque_id][int(plan_index)]
            )
    aggregates = {
        method: geometric(values) for method, values in method_values.items()
    }
    for method, value in aggregates.items():
        if abs(value - float(verdict["geometric_scores"][method])) > 1.0e-12:
            raise RuntimeError(f"aggregate drift for {method}")

    stock_losses = 0
    worst_stock_ratio = 1.0
    derived = 0
    derived_families = set()
    reuse_wins = 0
    reuse_families = set()
    selected_forms = set()
    for opaque_id, index in selected.items():
        candidate_score = recomputed_scores[opaque_id][index]
        reference_score = recomputed_scores[opaque_id][0]
        ratio = candidate_score / reference_score
        if ratio > 1.0 + 1.0e-9:
            stock_losses += 1
            worst_stock_ratio = max(worst_stock_ratio, ratio)
        plan = json.loads(
            (TRIAL / "candidate_plans" / f"{opaque_id}.json").read_text()
        )
        signature = receipt_by_id[opaque_id]["structural_signature_sha256"]
        selected_forms.add((signature, index))
        if plan["parameter_program"]["nodes"]:
            derived += 1
            family = provenance[opaque_id]["family"]
            derived_families.add(family)
            candidate_total = float(
                by_artifact[opaque_id][index]["objectives"]["amortized_total_us"]
            )
            reference_total = float(
                by_artifact[opaque_id][0]["objectives"]["amortized_total_us"]
            )
            if candidate_total < reference_total:
                reuse_wins += 1
                reuse_families.add(family)

    oracle_regret = aggregates["candidate"] / aggregates["exhaustive_oracle"]
    export_passes = sum(
        item["export"]["torch_export_status"] == "PASS"
        for item in provenance.values()
    )
    gates = {
        "artifact_count_24": len(by_artifact) == 24,
        "all_candidate_replay_receipts": len(candidates) == 24,
        "all_numerical_contracts": all(
            row["numerically_valid"] for row in rows
        ),
        "containment_hostile_probe": containment["status"]
        == "GHOST_OPERATOR_CONTAINMENT_V5_PASS",
        "torch_export_receipts_at_least_18": export_passes >= 18,
        "conditional_forms_at_least_4": len(selected_forms) >= 4,
        "derived_plans_at_least_6": derived >= 6,
        "derived_families_at_least_2": len(derived_families) >= 2,
        "reuse_wins_at_least_4": reuse_wins >= 4,
        "reuse_win_families_at_least_2": len(reuse_families) >= 2,
        "candidate_beats_stock": aggregates["candidate"]
        < aggregates["stock_reference"],
        "candidate_beats_fixed_compute": aggregates["candidate"]
        < aggregates["fixed_compute"],
        "candidate_beats_egraph": aggregates["candidate"]
        < aggregates["equality_saturation"],
        "candidate_not_worse_than_replay": aggregates["candidate"]
        <= aggregates["replay_memory"],
        "candidate_beats_fixed_portfolio_1pct": aggregates["candidate"]
        <= 0.99 * aggregates["fixed_signature_portfolio"],
        "oracle_regret_at_most_3pct": oracle_regret <= 1.03,
        "stock_losses_at_most_2": stock_losses <= 2,
        "worst_stock_loss_at_most_10pct": worst_stock_ratio <= 1.10,
    }
    if gates != verdict["gates"] or not all(gates.values()):
        raise RuntimeError("independent gate recomputation mismatch")
    hashes = {
        "candidate_receipts_sha256": sha(TRIAL / "candidate_receipts.jsonl"),
        "control_summary_sha256": sha(TRIAL / "control_summary.json"),
        "outcomes_sha256": sha(TRIAL / "outcomes.jsonl"),
        "manifest_sha256": sha(CORPUS / "manifest.tsv"),
        "private_audit_sha256": sha(CORPUS / "provenance.private.jsonl"),
    }
    for name, value in hashes.items():
        if verdict[name] != value:
            raise RuntimeError(f"verdict digest drift: {name}")
    output = {
        "status": "GHOST_OPERATOR_INDEPENDENT_RECOMPUTE_V5_1_PASS",
        "gates": gates,
        "geometric_scores": aggregates,
        "candidate_regret_vs_oracle": oracle_regret,
        "stock_losses": stock_losses,
        "worst_stock_ratio": worst_stock_ratio,
        "derived_selected": derived,
        "derived_families": sorted(derived_families),
        "reuse_wins": reuse_wins,
        "reuse_win_families": sorted(reuse_families),
        "selected_form_count": len(selected_forms),
        "torch_export_passes": export_passes,
        "v5_1_freeze_sha256": sha(HERE / "results/protocol_freeze_v5_1.txt"),
        "verdict_sha256": sha(TRIAL / "verdict.json"),
        **hashes,
    }
    path = HERE / "results/independent_recompute_v5_1.json"
    path.write_text(canonical(output) + "\n", encoding="utf-8")
    print(
        "GHOST_OPERATOR_INDEPENDENT_RECOMPUTE_V5_1 PASS"
        f" gates={sum(gates.values())}_of_{len(gates)}"
        f" candidate={aggregates['candidate']:.6f}"
        f" fixed={aggregates['fixed_signature_portfolio']:.6f}"
        f" replay={aggregates['replay_memory']:.6f}"
        f" oracle_regret={oracle_regret:.6f}"
        f" output_sha256={sha(path)}"
    )


if __name__ == "__main__":
    main()

