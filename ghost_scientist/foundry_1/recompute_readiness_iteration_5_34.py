#!/usr/bin/env python3
"""Recompute readiness after the local grammar falsification sequence."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_33.json"
    phase160_path = RESULTS / "phase160_local_grammar_emergence.json"
    phase161_path = RESULTS / "phase161_local_typed_template_transfer.json"
    phase162_path = RESULTS / "phase162_local_template_informativeness.json"
    prior = json.loads(prior_path.read_text())
    phase160 = json.loads(phase160_path.read_text())
    phase161 = json.loads(phase161_path.read_text())
    phase162 = json.loads(phase162_path.read_text())
    s160 = phase160["observed"]["summary"]
    s161 = phase161["observed"]["summary"]
    s162 = phase162["observed"]["summary"]
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and prior["progress"]["production_integrated_arms"] == 10
        and phase160["status"] == "LOCAL_GRAMMAR_EMERGENCE_VALID_NEGATIVE"
        and phase160["operationally_valid"] is True
        and s160["selected_non_chain_productions"] == 3
        and s160["candidate_only_heldout_nodes"] == 0
        and phase161["status"] == "LOCAL_TYPED_TEMPLATE_TRANSFER_POSITIVE"
        and phase161["operationally_valid"] is True
        and s161["candidate_only_template_matches"] == 2
        and s161["candidate_only_template_nodes"] == 3
        and phase161["decision"]["concrete_exact_tool_reuse_demonstrated"] is False
        and phase162["status"]
        == "LOCAL_TYPED_TEMPLATE_STRUCTURAL_ONLY_VALID_NEGATIVE"
        and phase162["operationally_valid"] is True
        and s162["candidate_heldout_matches"] == 2
        and s162["topology_only_heldout_matches"] == 2
        and s162["typed_rejections"] == 0
        and s162["candidate_information_bits"] == 0.0
        and phase162["decision"]["P6_advanced"] is False
    ):
        raise RuntimeError("iteration 5.34 inputs changed")
    progress = {
        **prior["progress"],
        "local_connected_dag_grammar_executed": True,
        "local_connected_dag_selected_productions": s160["selected_productions"],
        "local_connected_dag_non_chain_productions": s160[
            "selected_non_chain_productions"
        ],
        "local_exact_candidate_only_heldout_nodes": s160[
            "candidate_only_heldout_nodes"
        ],
        "local_typed_template_transfer_executed": True,
        "local_typed_template_candidate_only_matches": s161[
            "candidate_only_template_matches"
        ],
        "local_typed_template_candidate_only_nodes": s161[
            "candidate_only_template_nodes"
        ],
        "local_typed_template_concrete_reuse": False,
        "local_template_informativeness_ablation_executed": True,
        "local_template_typed_rejections": s162["typed_rejections"],
        "local_template_information_bits": s162["candidate_information_bits"],
        "local_template_structural_only": True,
    }
    result = {
        "version": "FOUNDRY_READINESS_ITERATION_5_34",
        "prior_sha256": sha(prior_path),
        "phase160_local_grammar_sha256": sha(phase160_path),
        "phase161_typed_template_sha256": sha(phase161_path),
        "phase162_informativeness_sha256": sha(phase162_path),
        "prerequisites": prior["prerequisites"],
        "progress": progress,
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "Local experimentation continued without accessing validation-v6 "
            "or validation-v7. Exhaustive connected induced DAG enumeration "
            "selected 27 topology productions, including three non-chain "
            "forms, but its nine exact tools reached no heldout node beyond "
            "the controls. Typed anti-unification over the non-chain forms "
            "then bound two unseen operator pairs across two heldout families "
            "and reconstructed both bodies byte-identically, reaching three "
            "nodes outside the exact, chain, and fixed controls. The frozen "
            "informativeness ablation showed that the learned type equality "
            "rejected zero topology-only matches and contributed zero bits: "
            "the positive was structural topology transfer, not typed "
            "prediction, concrete tool reuse, new operation semantics, or a "
            "runtime invention. P2, P6, V08, external intake, and prospective "
            "authorization are unchanged."
        ),
        "remaining_blockers": prior["remaining_blockers"],
        "remediation": {
            "required": True,
            "next_action": (
                "locally require learned constraints that beat a topology-only "
                "null on a fresh hash split before runtime specialization; "
                "externally, obtain the independently verified sponsor and "
                "corrected v2 bundle/provenance package unchanged"
            ),
            "forbidden_shortcuts": [
                "do not relabel parameter binding as autonomous tool construction",
                "do not call unseen operator-hole bindings new operation semantics",
                "do not benchmark runtime specialization until learned constraints add heldout information beyond topology",
                "do not access validation-v6 or validation-v7 or advance P2/P6 from these local post-outcome diagnostics",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_34.json").write_text(
        json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_34"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6 integrated=10/10"
        " local_exact=NEGATIVE local_template=STRUCTURAL_ONLY"
        " typed_bits=0 P6=false V08=pending prospective=false"
    )


if __name__ == "__main__":
    main()
