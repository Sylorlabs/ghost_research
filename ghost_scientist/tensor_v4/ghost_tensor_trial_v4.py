#!/usr/bin/env python3
"""Prospective Tensor v4 trial orchestrator.

The candidate runs twice per artifact inside the launcher-owned namespaces,
mount sandbox, resource limits, and outer/final seccomp filters. Evaluator
controls run outside that candidate boundary. Every legal partition is
compiled in a fresh process and cache, making the exhaustive oracle tractable
for the three-projection language.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import statistics
import subprocess
import sys
import tempfile
from collections.abc import Sequence
from typing import Any

from ghost_tensor_core_v4 import (
    canonical_json,
    identity_partition,
    load_artifact,
    packed_partition,
    plan_payload,
    random_partition,
    set_partitions,
    sha256_json,
)
from ghost_tensor_egraph_v4 import saturate


STATUS = "GHOST_TENSOR_TRIAL_V4"
CONTROL_NAMES = (
    "candidate",
    "strong_fixed_compiler",
    "fixed_equality_saturation",
    "random",
    "replay",
    "brute_exhaustive",
    "no_memory",
    "no_probe",
)
AGGREGATE_METRICS = (
    "latency_us_median",
    "compile_ms",
    "logical_gemm_kernels",
    "logical_linear_ops",
    "logical_split_views",
    "logical_head_views",
    "logical_transposes",
    "analytic_peak_live_tensor_bytes",
    "peak_rss_kb",
    "rss_delta_kb",
    "multiply_adds",
    "inductor_generated_kernel_count",
    "inductor_ir_nodes_pre_fusion",
    "inductor_num_bytes_accessed",
)


class TrialError(RuntimeError):
    pass


def file_sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_manifest(path: pathlib.Path, phase: str) -> list[pathlib.Path]:
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != (
        "opaque_id\tphase\tartifact_path\tartifact_sha256"
        "\tinput_shape\tprojection_outs"
    ):
        raise TrialError("manifest header mismatch")
    artifacts: list[pathlib.Path] = []
    seen: set[str] = set()
    for number, line in enumerate(lines[1:], 2):
        fields = line.split("\t")
        if len(fields) != 6 or fields[1] != phase or fields[0] in seen:
            raise TrialError(f"manifest line {number} phase/id violation")
        seen.add(fields[0])
        artifact = pathlib.Path(fields[2])
        if not artifact.is_absolute():
            artifact = (
                artifact.resolve()
                if artifact.exists()
                else (path.parent / artifact).resolve()
            )
        loaded, raw = load_artifact(artifact)
        if loaded.opaque_id != fields[0] or hashlib.sha256(raw).hexdigest() != fields[3]:
            raise TrialError(f"manifest line {number} artifact binding failed")
        artifacts.append(artifact)
    if not artifacts:
        raise TrialError("empty manifest")
    return artifacts


def run(
    command: Sequence[str],
    *,
    input_bytes: bytes | None = None,
    env: dict[str, str] | None = None,
    timeout: int = 180,
    pass_fds: tuple[int, ...] = (),
) -> subprocess.CompletedProcess[bytes]:
    completed = subprocess.run(
        command,
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        env=env,
        timeout=timeout,
        pass_fds=pass_fds,
    )
    if completed.returncode != 0:
        stderr = completed.stderr.decode("utf-8", "replace")[-3000:]
        raise TrialError(
            f"command failed rc={completed.returncode}: {command[0]}: {stderr}"
        )
    return completed


def sandbox(
    filter_path: pathlib.Path,
    bind_arguments: Sequence[str],
    program_arguments: Sequence[str],
    *,
    address_space: int = 268_435_456,
    cpu_seconds: int = 20,
) -> bytes:
    with filter_path.open("rb") as filter_file:
        command = [
            "timeout",
            "--signal=KILL",
            "25s",
            "unshare",
            "--user",
            "--map-root-user",
            "--net",
            "prlimit",
            f"--as={address_space}",
            f"--cpu={cpu_seconds}",
            "--nofile=32:32",
            "--",
            "bwrap",
            "--unshare-user",
            "--unshare-pid",
            "--unshare-ipc",
            "--unshare-uts",
            "--die-with-parent",
            "--new-session",
            "--as-pid-1",
            "--cap-drop",
            "ALL",
            "--clearenv",
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
            "--tmpfs",
            "/work",
            "--chdir",
            "/work",
            *bind_arguments,
            "--seccomp",
            str(filter_file.fileno()),
            *program_arguments,
        ]
        return run(
            command,
            timeout=30,
            pass_fds=(filter_file.fileno(),),
        ).stdout


def containment_receipt(
    *,
    filter_path: pathlib.Path,
    candidate: pathlib.Path,
    probe_binary: pathlib.Path,
) -> dict[str, object]:
    outer = sandbox(
        filter_path,
        ("--ro-bind", str(probe_binary.resolve()), "/program"),
        ("/program",),
        address_space=134_217_728,
        cpu_seconds=8,
    ).decode("utf-8")
    if "GHOST_TENSOR_OUTER_PROBE_V4 PASS denials=5" not in outer:
        raise TrialError("outer seccomp probe did not pass")
    final = sandbox(
        filter_path,
        ("--ro-bind", str(candidate.resolve()), "/candidate.py"),
        ("/usr/bin/python3", "-B", "/candidate.py", "--probe-final"),
        address_space=134_217_728,
        cpu_seconds=8,
    ).decode("utf-8")
    if "GHOST_TENSOR_FINAL_PROBE_V4 PASS policy=default_deny denials=6" not in final:
        raise TrialError("final seccomp probe did not pass")
    host_namespace = os.readlink("/proc/self/ns/net")
    child_namespace = run(
        (
            "unshare",
            "--user",
            "--map-root-user",
            "--net",
            "readlink",
            "/proc/self/ns/net",
        )
    ).stdout.decode("ascii").strip()
    if child_namespace == host_namespace:
        raise TrialError("network namespace did not change")
    return {
        "outer_default_deny": True,
        "outer_denials": 5,
        "final_default_deny": True,
        "final_denials": 6,
        "network_namespace_distinct": True,
        "mount_namespace": "bubblewrap_read_only_runtime_and_two_visible_inputs",
        "filter_sha256": file_sha(filter_path),
    }


def candidate_output(
    artifact: pathlib.Path,
    grammar: pathlib.Path,
    candidate: pathlib.Path,
    filter_path: pathlib.Path,
) -> bytes:
    return sandbox(
        filter_path,
        (
            "--ro-bind",
            str(candidate.resolve()),
            "/candidate.py",
            "--ro-bind",
            str(artifact.resolve()),
            "/artifact.json",
            "--ro-bind",
            str(grammar.resolve()),
            "/grammar.json",
        ),
        (
            "/usr/bin/python3",
            "-B",
            "/candidate.py",
            "/artifact.json",
            "/grammar.json",
        ),
    )


def verify_candidate(
    artifact: pathlib.Path,
    grammar_sha: str,
    candidate_raw: bytes,
    verifier: pathlib.Path,
) -> dict[str, Any]:
    output = run(
        (
            sys.executable,
            "-B",
            str(verifier),
            "--artifact",
            str(artifact),
            "--grammar-sha",
            grammar_sha,
        ),
        input_bytes=candidate_raw,
        timeout=60,
    ).stdout
    return json.loads(output)


def measure(
    artifact: pathlib.Path,
    plan: dict[str, object],
    evaluator: pathlib.Path,
    *,
    repetitions: int,
) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="ghost-tensor-v4-inductor-") as cache:
        environment = os.environ.copy()
        environment.update(
            {
                "TORCHINDUCTOR_CACHE_DIR": cache,
                "OMP_NUM_THREADS": "1",
                "MKL_NUM_THREADS": "1",
                "OPENBLAS_NUM_THREADS": "1",
            }
        )
        output = run(
            (
                sys.executable,
                "-B",
                str(evaluator),
                "measure",
                str(artifact),
                "plan",
                "--plan-json",
                canonical_json(plan),
                "--backend",
                "inductor",
                "--repetitions",
                str(repetitions),
            ),
            env=environment,
            timeout=180,
        ).stdout
    metrics = json.loads(output)
    if metrics.get("status") != "GHOST_TENSOR_MEASURE_V4":
        raise TrialError("evaluator returned the wrong status")
    return metrics


def plan_sha(plan: dict[str, object]) -> str:
    return sha256_json(plan)


def control_plan_map(
    artifact: Any,
    candidate_plan: dict[str, object],
    measured: dict[str, dict[str, Any]],
    artifact_sha: str,
) -> tuple[dict[str, str], dict[str, object]]:
    count = len(artifact.projections)
    identity = plan_payload(identity_partition(count), count)
    packed = plan_payload(packed_partition(count), count)
    egraph_groups, egraph_receipt = saturate(count)
    egraph = plan_payload(egraph_groups, count)
    random_seed = int(artifact_sha[:16], 16) ^ 0x72616E646F6D5F34
    random_plan = plan_payload(random_partition(count, random_seed), count)
    brute_sha = min(
        measured,
        key=lambda digest: (
            float(measured[digest]["latency_us_median"]),
            float(measured[digest]["compile_ms"]),
            digest,
        ),
    )
    controls = {
        "candidate": plan_sha(candidate_plan),
        "strong_fixed_compiler": plan_sha(identity),
        "fixed_equality_saturation": plan_sha(egraph),
        "random": plan_sha(random_plan),
        "replay": plan_sha(packed),
        "brute_exhaustive": brute_sha,
        "no_memory": plan_sha(identity),
        "no_probe": plan_sha(egraph),
    }
    if any(digest not in measured for digest in controls.values()):
        raise TrialError("a control selected an unmeasured plan")
    return controls, egraph_receipt


def aggregate(
    records: list[dict[str, Any]],
    containment: dict[str, object],
    *,
    phase: str,
    repetitions: int,
) -> dict[str, Any]:
    failures = [record for record in records if record.get("failure") is not None]
    valid = [record for record in records if record.get("failure") is None]
    totals: dict[str, dict[str, float]] = {}
    maxima: dict[str, dict[str, float]] = {}
    for control in CONTROL_NAMES:
        totals[control] = {}
        maxima[control] = {}
        for metric in AGGREGATE_METRICS:
            values = [
                float(record["measurements"][record["controls"][control]].get(metric, 0))
                for record in valid
            ]
            totals[control][metric] = sum(values)
            maxima[control][metric] = max(values, default=0.0)
    candidate_latency = totals["candidate"].get("latency_us_median", 0.0)
    fixed_names = (
        "strong_fixed_compiler",
        "fixed_equality_saturation",
        "replay",
        "no_memory",
        "no_probe",
    )
    fixed_portfolio_name = min(
        fixed_names,
        key=lambda name: totals[name].get("latency_us_median", float("inf")),
    )
    fixed_latency = totals[fixed_portfolio_name].get("latency_us_median", 0.0)
    improvement = (
        (fixed_latency - candidate_latency) / fixed_latency if fixed_latency else 0.0
    )
    chosen_plans = {
        record["controls"]["candidate"] for record in valid
    }
    replay_equal = sum(bool(record.get("candidate_replay_equal")) for record in valid)
    numerical_max = max(
        (
            float(
                record["measurements"][record["controls"]["candidate"]][
                    "compiled_max_abs_error"
                ]
            )
            for record in valid
        ),
        default=float("inf"),
    )
    wins = ties = losses = 0
    for record in valid:
        candidate_value = float(
            record["measurements"][record["controls"]["candidate"]][
                "latency_us_median"
            ]
        )
        fixed_value = float(
            record["measurements"][record["controls"][fixed_portfolio_name]][
                "latency_us_median"
            ]
        )
        if candidate_value < fixed_value:
            wins += 1
        elif candidate_value > fixed_value:
            losses += 1
        else:
            ties += 1
    reuse_calls = 1000
    amortized_us: dict[str, float] = {}
    for control in CONTROL_NAMES:
        amortized_us[control] = (
            totals[control].get("compile_ms", 0.0) * 1000.0
            + reuse_calls * totals[control].get("latency_us_median", 0.0)
        )
    verdict = (
        not failures
        and len(valid) == len(records)
        and replay_equal == len(valid)
        and len(chosen_plans) >= 2
        and numerical_max <= 1e-5
        and improvement > 0.001
        and candidate_latency
        < totals["strong_fixed_compiler"].get("latency_us_median", 0.0)
        and candidate_latency
        < totals["fixed_equality_saturation"].get("latency_us_median", 0.0)
    )
    return {
        "status": f"{STATUS}_{'PASS' if verdict else 'FAIL'}",
        "phase": phase,
        "artifact_count": len(records),
        "valid_artifact_count": len(valid),
        "failure_count": len(failures),
        "repetitions": repetitions,
        "candidate_replay_equal": replay_equal,
        "candidate_distinct_plan_count": len(chosen_plans),
        "candidate_compiled_max_abs_error": numerical_max,
        "fixed_portfolio_definition": "lowest_aggregate_predeclared_fixed_control",
        "fixed_portfolio_winner": fixed_portfolio_name,
        "candidate_latency_sum_us": candidate_latency,
        "fixed_portfolio_latency_sum_us": fixed_latency,
        "candidate_improvement_fraction": improvement,
        "wins_ties_losses_vs_fixed_portfolio": [wins, ties, losses],
        "reuse_calls": reuse_calls,
        "amortized_compile_plus_runtime_us": amortized_us,
        "control_metric_sums": totals,
        "control_metric_maxima": maxima,
        "containment": containment,
        "control_overlap_is_expected": {
            "strong_fixed_compiler_equals_no_memory": True,
            "fixed_equality_saturation_equals_no_probe": True,
            "replay_is_development_global_best_pack_all": True,
        },
        "claim_scope": {
            "transformer_is_target_architecture": False,
            "gpu_speed": False,
            "pretrained_weight_performance": False,
            "autonomous_primitive_invention": False,
            "conditional_reusable_tensor_rewrite": True,
        },
    }


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--phase", choices=("VALIDATION", "HELDOUT"), required=True)
    parser.add_argument("--grammar", required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--evaluator", required=True)
    parser.add_argument("--verifier", required=True)
    parser.add_argument("--filter", required=True)
    parser.add_argument("--probe-binary", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--repetitions", type=int, default=9)
    args = parser.parse_args(argv)

    manifest = pathlib.Path(args.manifest).resolve()
    grammar = pathlib.Path(args.grammar).resolve()
    candidate = pathlib.Path(args.candidate).resolve()
    evaluator = pathlib.Path(args.evaluator).resolve()
    verifier = pathlib.Path(args.verifier).resolve()
    filter_path = pathlib.Path(args.filter).resolve()
    probe_binary = pathlib.Path(args.probe_binary).resolve()
    output_dir = pathlib.Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    ledger_path = output_dir / "ledger.jsonl"
    summary_path = output_dir / "summary.json"

    artifacts = parse_manifest(manifest, args.phase)
    grammar_sha = file_sha(grammar)
    containment = containment_receipt(
        filter_path=filter_path,
        candidate=candidate,
        probe_binary=probe_binary,
    )
    records: list[dict[str, Any]] = []
    ledger_path.write_text("", encoding="utf-8")
    for artifact_index, artifact_path in enumerate(artifacts, 1):
        artifact, artifact_raw = load_artifact(artifact_path)
        artifact_sha = hashlib.sha256(artifact_raw).hexdigest()
        record: dict[str, Any] = {
            "status": "GHOST_TENSOR_TRIAL_ARTIFACT_V4",
            "phase": args.phase,
            "opaque_id": artifact.opaque_id,
            "artifact_sha256": artifact_sha,
            "failure": None,
        }
        try:
            first = candidate_output(
                artifact_path, grammar, candidate, filter_path
            )
            second = candidate_output(
                artifact_path, grammar, candidate, filter_path
            )
            record["candidate_replay_equal"] = first == second
            if first != second:
                raise TrialError("candidate output was not byte-identical")
            candidate_payload = json.loads(first)
            verification = verify_candidate(
                artifact_path, grammar_sha, first, verifier
            )
            partitions = set_partitions(len(artifact.projections))
            measurements: dict[str, dict[str, Any]] = {}
            for groups in partitions:
                plan = plan_payload(groups, len(artifact.projections))
                digest = plan_sha(plan)
                measurements[digest] = measure(
                    artifact_path,
                    plan,
                    evaluator,
                    repetitions=args.repetitions,
                )
            controls, egraph_receipt = control_plan_map(
                artifact,
                candidate_payload["plan"],
                measurements,
                artifact_sha,
            )
            record.update(
                {
                    "candidate_output": candidate_payload,
                    "verification": verification,
                    "controls": controls,
                    "measurements": measurements,
                    "equality_saturation_receipt": egraph_receipt,
                }
            )
        except Exception as exc:
            record["failure"] = f"{type(exc).__name__}: {exc}"
        records.append(record)
        with ledger_path.open("a", encoding="utf-8") as ledger:
            ledger.write(canonical_json(record) + "\n")
        print(
            "GHOST_TENSOR_TRIAL_PROGRESS_V4"
            f" phase={args.phase} artifact={artifact.opaque_id}"
            f" index={artifact_index}_of_{len(artifacts)}"
            f" status={'FAIL' if record['failure'] else 'PASS'}",
            flush=True,
        )

    summary = aggregate(
        records,
        containment,
        phase=args.phase,
        repetitions=args.repetitions,
    )
    summary.update(
        {
            "manifest_sha256": file_sha(manifest),
            "grammar_sha256": grammar_sha,
            "candidate_sha256": file_sha(candidate),
            "evaluator_sha256": file_sha(evaluator),
            "verifier_sha256": file_sha(verifier),
            "ledger_sha256": file_sha(ledger_path),
        }
    )
    summary_path.write_text(canonical_json(summary) + "\n", encoding="utf-8")
    print(canonical_json(summary))
    if summary["status"] != f"{STATUS}_PASS":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
