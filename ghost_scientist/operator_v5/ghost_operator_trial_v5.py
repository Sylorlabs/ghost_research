#!/usr/bin/env python3
"""Integrated prospective heldout trial for Ghost Scientist Operator v5."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile
from collections import defaultdict
from typing import Any

from ghost_operator_core_v5 import (
    canonical_json,
    file_sha256,
    load_artifact,
    load_plan_text,
    sha256_json,
)
from ghost_operator_development_v5 import load_manifest, measure_manifest
from ghost_operator_freeze_v5 import verify as verify_freeze
from ghost_operator_synthesis_v5 import enumerate_plans, structural_signature
from ghost_operator_validate_grammar_v5 import validate as validate_grammar


def _compile_containment(root: pathlib.Path, build: pathlib.Path) -> dict[str, object]:
    containment = root / "containment"
    env = dict(os.environ)
    env.update(
        {
            "ZIG_GLOBAL_CACHE_DIR": str(build / "zig-global"),
            "ZIG_LOCAL_CACHE_DIR": str(build / "zig-local"),
        }
    )
    allowlist = build / "allowlist"
    probe = build / "probe"
    policy = build / "policy.bpf"
    commands = [
        [
            "zig",
            "build-exe",
            str(containment / "ghost_operator_allowlist_v5.zig"),
            "-lc",
            "-lseccomp",
            f"-femit-bin={allowlist}",
        ],
        [
            "zig",
            "build-exe",
            str(containment / "ghost_operator_probe_v5.zig"),
            f"-femit-bin={probe}",
        ],
    ]
    for command in commands:
        completed = subprocess.run(
            command, env=env, text=True, capture_output=True, timeout=120, check=False
        )
        if completed.returncode:
            raise RuntimeError(f"containment compile failed: {completed.stderr[-2000:]}")
    generated = subprocess.run(
        [str(allowlist), str(policy)],
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )
    if generated.returncode or "PASS" not in generated.stdout:
        raise RuntimeError(f"allowlist generation failed: {generated.stderr[-1000:]}")
    with policy.open("rb") as policy_file:
        command = _bwrap_prefix(policy_file.fileno()) + [
            "--ro-bind",
            str(probe),
            "/probe",
            "/probe",
        ]
        tested = subprocess.run(
            command,
            pass_fds=(policy_file.fileno(),),
            text=True,
            capture_output=True,
            timeout=30,
            check=False,
        )
    expected = (
        "fork=EPERM",
        "socket=EPERM",
        "unshare=EPERM",
        "kill=EPERM",
        "clock_gettime=EPERM",
        "GHOST_OPERATOR_OUTER_PROBE_V5 PASS",
    )
    if tested.returncode or any(item not in tested.stdout for item in expected):
        raise RuntimeError(
            f"containment hostile probe failed: {tested.stdout[-1000:]} "
            f"{tested.stderr[-1000:]}"
        )
    return {
        "status": "GHOST_OPERATOR_CONTAINMENT_V5_PASS",
        "allowlist_sha256": file_sha256(containment / "ghost_operator_allowlist_v5.zig"),
        "probe_sha256": file_sha256(containment / "ghost_operator_probe_v5.zig"),
        "policy_sha256": file_sha256(policy),
        "probe_stdout": tested.stdout,
        "network_boundary": "socket syscall denied by default-deny seccomp",
        "network_namespace": (
            "host unavailable: bubblewrap net namespace initialization denied "
            "by host netlink policy"
        ),
    }


def _bwrap_prefix(seccomp_fd: int) -> list[str]:
    return [
        "bwrap",
        "--die-with-parent",
        "--new-session",
        "--unshare-user",
        "--unshare-pid",
        "--unshare-ipc",
        "--unshare-uts",
        "--unshare-cgroup",
        "--ro-bind",
        "/usr",
        "/usr",
        "--ro-bind",
        "/lib",
        "/lib",
        "--ro-bind",
        "/lib64",
        "/lib64",
        "--proc",
        "/proc",
        "--dev",
        "/dev",
        "--tmpfs",
        "/tmp",
        "--dir",
        "/work",
        "--chdir",
        "/work",
        "--clearenv",
        "--setenv",
        "PYTHONHASHSEED",
        "0",
        "--seccomp",
        str(seccomp_fd),
    ]


def _contained_candidate(
    root: pathlib.Path,
    artifact_path: pathlib.Path,
    grammar_path: pathlib.Path,
    policy_path: pathlib.Path,
) -> tuple[str, str]:
    candidate = root / "ghost_operator_candidate_v5.py"
    with policy_path.open("rb") as policy_file:
        command = _bwrap_prefix(policy_file.fileno()) + [
            "--ro-bind",
            str(candidate),
            "/work/candidate.py",
            "--ro-bind",
            str(artifact_path),
            "/work/artifact.json",
            "--ro-bind",
            str(grammar_path),
            "/work/grammar.json",
            "/usr/bin/python3",
            "-I",
            "/work/candidate.py",
            "/work/artifact.json",
            "/work/grammar.json",
        ]
        completed = subprocess.run(
            command,
            pass_fds=(policy_file.fileno(),),
            text=True,
            capture_output=True,
            timeout=30,
            check=False,
        )
    if completed.returncode:
        raise RuntimeError(
            f"contained candidate failed for {artifact_path.name}: "
            f"{completed.stderr[-2000:]}"
        )
    return completed.stdout.strip(), completed.stderr


def _load_provenance(path: pathlib.Path) -> dict[str, dict[str, Any]]:
    result = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        row = json.loads(line)
        if row.get("status") != "GHOST_OPERATOR_PROVENANCE_V5":
            raise ValueError(f"private audit line {number} status mismatch")
        if row["opaque_id"] in result:
            raise ValueError("duplicate private provenance id")
        result[row["opaque_id"]] = row
    return result


def _selected_rows(
    outcomes_path: pathlib.Path, selected: dict[str, int]
) -> dict[str, dict[int, dict[str, Any]]]:
    result: dict[str, dict[int, dict[str, Any]]] = defaultdict(dict)
    for line in outcomes_path.read_text(encoding="utf-8").splitlines():
        row = json.loads(line)
        result[row["opaque_id"]][int(row["plan_index"])] = row
    for opaque_id, index in selected.items():
        if index not in result[opaque_id]:
            raise ValueError(f"selected outcome missing for {opaque_id}")
    return result


def run_trial(
    manifest: pathlib.Path,
    private_audit: pathlib.Path,
    grammar: pathlib.Path,
    fixed_portfolio: pathlib.Path,
    freeze_record: pathlib.Path,
    output_root: pathlib.Path,
    *,
    repetitions: int,
) -> None:
    root = pathlib.Path(__file__).resolve().parent
    verify_freeze(root, freeze_record)
    output_root.mkdir(parents=True, exist_ok=False)
    plan_dir = output_root / "candidate_plans"
    plan_dir.mkdir()
    candidate_receipts = []
    selected: dict[str, int] = {}
    selected_plans: dict[str, dict[str, Any]] = {}
    with tempfile.TemporaryDirectory(prefix="ghost-operator-containment-") as directory:
        build = pathlib.Path(directory)
        containment_receipt = _compile_containment(root, build)
        policy = build / "policy.bpf"
        for artifact_path in load_manifest(manifest, "HELDOUT"):
            artifact, raw = load_artifact(artifact_path)
            plan_text, stderr = _contained_candidate(
                root, artifact_path, grammar, policy
            )
            candidate_plan = load_plan_text(plan_text, artifact)
            choices = enumerate_plans(artifact)
            matches = [
                index
                for index, item in enumerate(choices)
                if canonical_json(item) == canonical_json(candidate_plan)
            ]
            if len(matches) != 1:
                raise ValueError(
                    f"candidate plan is not one exact evaluator construction: "
                    f"{artifact.opaque_id}"
                )
            plan_index = matches[0]
            selected[artifact.opaque_id] = plan_index
            selected_plans[artifact.opaque_id] = candidate_plan
            plan_path = plan_dir / f"{artifact.opaque_id}.json"
            plan_path.write_text(
                canonical_json(candidate_plan) + "\n", encoding="utf-8"
            )
            candidate_receipts.append(
                {
                    "status": "GHOST_OPERATOR_CONTAINED_CANDIDATE_V5",
                    "opaque_id": artifact.opaque_id,
                    "artifact_sha256": hashlib.sha256(raw).hexdigest(),
                    "plan_index": plan_index,
                    "plan_sha256": sha256_json(candidate_plan),
                    "candidate_stderr": stderr,
                    "contained": True,
                }
            )
            print(
                "GHOST_OPERATOR_TRIAL_CANDIDATE_V5"
                f" artifact={artifact.opaque_id} plan_index={plan_index}",
                flush=True,
            )
    (output_root / "containment.json").write_text(
        canonical_json(containment_receipt) + "\n", encoding="utf-8"
    )
    candidate_receipt_path = output_root / "candidate_receipts.jsonl"
    candidate_receipt_path.write_text(
        "\n".join(canonical_json(item) for item in candidate_receipts) + "\n",
        encoding="utf-8",
    )

    outcomes_path = output_root / "outcomes.jsonl"
    measure_manifest(
        manifest,
        outcomes_path,
        backend="inductor",
        repetitions=repetitions,
        inner_iterations=None,
        limit_artifacts=None,
        phase="HELDOUT",
        start_artifact=0,
    )
    summary_path = output_root / "control_summary.json"
    validate_grammar(
        manifest,
        outcomes_path,
        grammar,
        summary_path,
        "HELDOUT",
        fixed_portfolio,
    )
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    provenance = _load_provenance(private_audit)
    outcome_rows = _selected_rows(outcomes_path, selected)

    numerical_failures = 0
    stock_losses = 0
    worst_stock_ratio = 1.0
    derived_selected = 0
    derived_families: set[str] = set()
    reuse_wins = 0
    reuse_win_families: set[str] = set()
    selected_forms: set[tuple[str, int]] = set()
    for opaque_id, index in selected.items():
        candidate_row = outcome_rows[opaque_id][index]
        reference_row = outcome_rows[opaque_id][0]
        if not candidate_row["numerically_valid"]:
            numerical_failures += 1
        candidate_score = float(candidate_row["score"])
        reference_score = float(reference_row["score"])
        ratio = candidate_score / reference_score
        if ratio > 1.0 + 1.0e-9:
            stock_losses += 1
            worst_stock_ratio = max(worst_stock_ratio, ratio)
        plan = selected_plans[opaque_id]
        signature = hashlib.sha256(
            structural_signature(load_artifact(
                next(
                    path
                    for path in load_manifest(manifest, "HELDOUT")
                    if load_artifact(path)[0].opaque_id == opaque_id
                )
            )[0]).encode()
        ).hexdigest()
        selected_forms.add((signature, index))
        if plan["parameter_program"]["nodes"]:
            derived_selected += 1
            family = provenance[opaque_id]["family"]
            derived_families.add(family)
            if (
                float(candidate_row["objectives"]["amortized_total_us"])
                < float(reference_row["objectives"]["amortized_total_us"])
            ):
                reuse_wins += 1
                reuse_win_families.add(family)

    export_passes = sum(
        row["export"]["torch_export_status"] == "PASS"
        for row in provenance.values()
    )
    scores = summary["geometric_scores"]
    gates = {
        "artifact_count_24": summary["artifact_count"] == 24,
        "all_candidate_replay_receipts": len(candidate_receipts) == 24,
        "all_numerical_contracts": numerical_failures == 0,
        "containment_hostile_probe": containment_receipt["status"]
        == "GHOST_OPERATOR_CONTAINMENT_V5_PASS",
        "torch_export_receipts_at_least_18": export_passes >= 18,
        "conditional_forms_at_least_4": len(selected_forms) >= 4,
        "derived_plans_at_least_6": derived_selected >= 6,
        "derived_families_at_least_2": len(derived_families) >= 2,
        "reuse_wins_at_least_4": reuse_wins >= 4,
        "reuse_win_families_at_least_2": len(reuse_win_families) >= 2,
        "candidate_beats_stock": scores["candidate"] < scores["stock_reference"],
        "candidate_beats_fixed_compute": scores["candidate"]
        < scores["fixed_compute"],
        "candidate_beats_egraph": scores["candidate"]
        < scores["equality_saturation"],
        "candidate_not_worse_than_replay": scores["candidate"]
        <= scores["replay_memory"],
        "candidate_beats_fixed_portfolio_1pct": scores["candidate"]
        <= 0.99 * scores["fixed_signature_portfolio"],
        "oracle_regret_at_most_3pct": summary["candidate_regret_vs_oracle"] <= 1.03,
        "stock_losses_at_most_2": stock_losses <= 2,
        "worst_stock_loss_at_most_10pct": worst_stock_ratio <= 1.10,
    }
    verdict = {
        "status": (
            "GHOST_OPERATOR_HELDOUT_V5_PASS"
            if all(gates.values())
            else "GHOST_OPERATOR_HELDOUT_V5_FAIL"
        ),
        "gates": gates,
        "geometric_scores": scores,
        "candidate_regret_vs_oracle": summary["candidate_regret_vs_oracle"],
        "stock_losses": stock_losses,
        "worst_stock_ratio": worst_stock_ratio,
        "derived_selected": derived_selected,
        "derived_families": sorted(derived_families),
        "reuse_wins": reuse_wins,
        "reuse_win_families": sorted(reuse_win_families),
        "selected_form_count": len(selected_forms),
        "torch_export_passes": export_passes,
        "manifest_sha256": file_sha256(manifest),
        "private_audit_sha256": file_sha256(private_audit),
        "grammar_sha256": file_sha256(grammar),
        "fixed_portfolio_sha256": file_sha256(fixed_portfolio),
        "freeze_record_sha256": file_sha256(freeze_record),
        "candidate_receipts_sha256": file_sha256(candidate_receipt_path),
        "outcomes_sha256": file_sha256(outcomes_path),
        "control_summary_sha256": file_sha256(summary_path),
    }
    verdict_path = output_root / "verdict.json"
    verdict_path.write_text(canonical_json(verdict) + "\n", encoding="utf-8")
    print(
        f"{verdict['status']}"
        f" gates_passed={sum(gates.values())}_of_{len(gates)}"
        f" candidate_score={scores['candidate']:.6f}"
        f" fixed_score={scores['fixed_signature_portfolio']:.6f}"
        f" replay_score={scores['replay_memory']:.6f}"
        f" oracle_regret={summary['candidate_regret_vs_oracle']:.6f}"
        f" verdict_sha256={file_sha256(verdict_path)}",
        flush=True,
    )
    if not all(gates.values()):
        raise SystemExit(1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=pathlib.Path)
    parser.add_argument("private_audit", type=pathlib.Path)
    parser.add_argument("grammar", type=pathlib.Path)
    parser.add_argument("fixed_portfolio", type=pathlib.Path)
    parser.add_argument("freeze_record", type=pathlib.Path)
    parser.add_argument("output_root", type=pathlib.Path)
    parser.add_argument("--repetitions", type=int, default=11)
    args = parser.parse_args()
    run_trial(
        args.manifest.resolve(),
        args.private_audit.resolve(),
        args.grammar.resolve(),
        args.fixed_portfolio.resolve(),
        args.freeze_record.resolve(),
        args.output_root.resolve(),
        repetitions=args.repetitions,
    )


if __name__ == "__main__":
    main()
