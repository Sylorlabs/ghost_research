#!/usr/bin/env python3
"""Run the pre-frozen post-failure A1 numerical stability remediation."""

from __future__ import annotations

import hashlib
import json
import math
import pathlib
import sys
import tempfile
from typing import Any

import torch

from a1_pattern_first_fold import (
    canonical,
    capture,
    descriptor,
    folded_actual,
    primary_lower,
    v5_execute,
)
from independent_a1_fold_lowering import (
    compare as independent_compare,
    lower as independent_lower,
)
from independent_framework_runtime import primary_compare
from phase146_a1_pattern_first_fold_conformance import hostile_batch
from phase63_pareto_motif_calibration import workloads
from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
AMENDMENT = (
    HERE
    / "arm_adapter_fixtures/A1_FOLD_NUMERICAL_STABILITY_AMENDMENT_V1.json"
)
FREEZE = HERE / "results/a1_fold_numerical_stability_amendment_v1_freeze.json"
BASE_PROTOCOL = HERE / "arm_adapter_fixtures/A1_PATTERN_FIRST_FOLD_PROTOCOL_V1.json"
GRAMMAR = HERE / "../operator_v5_1/results/frozen_grammar_v5_1.json"
WORKER_RESULT = HERE / "results/phase147_a1_fold_numerical_stability_worker.json"
RESULT = HERE / "results/phase147_a1_fold_numerical_stability_remediation.json"

OPERATOR = (HERE / "../operator_v5").resolve()
if str(OPERATOR) not in sys.path:
    sys.path.insert(0, str(OPERATOR))

from ghost_operator_candidate_v5 import enumerate_plans as candidate_enumerate  # noqa: E402
from ghost_operator_core_v5 import (  # noqa: E402
    TensorProgramModule,
    canonical_json,
    load_artifact,
    load_plan_text,
    materialize_inputs,
    reference_plan,
)
from ghost_operator_synthesis_v5 import enumerate_plans as evaluator_enumerate  # noqa: E402


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def randomized(value: Any, generator: torch.Generator) -> Any:
    if isinstance(value, torch.Tensor):
        if value.dtype.is_floating_point:
            return torch.randn(
                value.shape,
                dtype=value.dtype,
                device=value.device,
                generator=generator,
            ).requires_grad_(value.requires_grad)
        return value.detach().clone()
    if isinstance(value, tuple):
        return tuple(randomized(item, generator) for item in value)
    if isinstance(value, list):
        return [randomized(item, generator) for item in value]
    if isinstance(value, dict):
        return {
            key: randomized(item, generator) for key, item in value.items()
        }
    return value


def invocation_seed(
    artifact_id: str, conv_name: str, ordinal: int
) -> tuple[int, str]:
    label = canonical(["A1-FOLD", artifact_id, conv_name, ordinal])
    digest = hashlib.sha256(label.encode()).digest()
    return int.from_bytes(digest[:8], "big") % (2**63), hashlib.sha256(
        label.encode()
    ).hexdigest()


def as_tuple(value: Any) -> tuple[torch.Tensor, ...]:
    return value if isinstance(value, tuple) else (value,)


def combined_tolerance_evaluate(
    artifact_path: pathlib.Path,
    payload: dict[str, object],
    *,
    absolute_tolerance: float,
    relative_tolerance: float,
) -> dict[str, object]:
    artifact, _ = load_artifact(artifact_path)
    primary_plans = candidate_enumerate(payload)
    independent_plans = evaluator_enumerate(artifact)
    if canonical(primary_plans) != canonical(independent_plans):
        raise RuntimeError("numerical evaluator plan sets disagree")
    plan = load_plan_text(canonical_json(primary_plans[1]), artifact)
    inputs = materialize_inputs(artifact)
    reference, _ = TensorProgramModule.build(
        artifact, reference_plan(artifact)
    )
    candidate, _ = TensorProgramModule.build(artifact, plan)
    with torch.no_grad():
        expected = as_tuple(reference(*inputs))
        actual = as_tuple(candidate(*inputs))
    if len(expected) != len(actual):
        raise RuntimeError("output arity mismatch")
    maximum_absolute_error = 0.0
    maximum_allowed_error = 0.0
    maximum_excess = 0.0
    for contract, left, right in zip(
        artifact.outputs, expected, actual, strict=True
    ):
        if (
            left.shape != right.shape
            or left.dtype != right.dtype
            or left.device != right.device
            or left.layout != right.layout
            or left.stride() != right.stride()
            or not right.isfinite().all().item()
        ):
            raise RuntimeError("combined-tolerance metadata contract failed")
        if contract.layout == "last_dim_stride_1" and right.stride()[-1] != 1:
            raise RuntimeError("declared output layout failed")
        difference = (left - right).abs()
        allowance = absolute_tolerance + relative_tolerance * left.abs()
        maximum_absolute_error = max(
            maximum_absolute_error, float(difference.max().item())
        )
        maximum_allowed_error = max(
            maximum_allowed_error, float(allowance.max().item())
        )
        maximum_excess = max(
            maximum_excess,
            float(torch.clamp(difference - allowance, min=0).max().item()),
        )
    return {
        "combined_tolerance_passed": maximum_excess == 0.0,
        "maximum_absolute_error": maximum_absolute_error,
        "maximum_allowed_error": maximum_allowed_error,
        "maximum_excess": maximum_excess,
        "absolute_tolerance": absolute_tolerance,
        "relative_tolerance": relative_tolerance,
        "finite_outputs": True,
        "exact_metadata_and_layout": True,
    }


def worker() -> None:
    amendment = json.loads(AMENDMENT.read_text())
    base = json.loads(BASE_PROTOCOL.read_text())
    original = json.loads(GRAMMAR.read_text())
    target_artifact = base["targets"][0]["artifact_id"]
    instantiated, unsupported = workloads()
    selected = [
        workload
        for suite, workload in instantiated
        if f"{suite}:{workload['family']}" == target_artifact
    ]
    if len(selected) != 1:
        raise RuntimeError("frozen source artifact is not unique")
    workload = selected[0]
    module = torch.export.export(
        workload["model"],
        workload["args"],
        workload["kwargs"],
        strict=True,
    ).module()
    absolute = amendment["amended_synthetic_numerical_contract"][
        "absolute_tolerance"
    ]
    relative = amendment["amended_synthetic_numerical_contract"][
        "relative_tolerance"
    ]
    real_rows = []
    panel_rows = []
    original_payload = None
    with tempfile.TemporaryDirectory(prefix="foundry-a1-numeric-") as raw_dir:
        directory = pathlib.Path(raw_dir)
        for target in base["targets"]:
            desc = descriptor(
                module,
                target["artifact_id"],
                target["conv_node"],
                target["batch_norm_node"],
            )
            comparisons = []
            for ordinal in range(
                amendment["unchanged_requirements"][
                    "real_source_invocations_per_target"
                ]
            ):
                seed, seed_sha256 = invocation_seed(
                    target["artifact_id"], target["conv_node"], ordinal
                )
                generator = torch.Generator(device="cpu").manual_seed(seed)
                args = randomized(workload["args"], generator)
                kwargs = randomized(workload["kwargs"], generator)
                values = capture(module, args, kwargs)
                expected = values[target["batch_norm_node"]][0]
                actual = folded_actual(desc, values)
                primary_receipt = primary_compare(expected, actual)
                independent_receipt = independent_compare(
                    expected,
                    actual,
                    values[desc["x"].name],
                    tolerance=amendment["unchanged_requirements"][
                        "real_source_maximum_absolute_error"
                    ],
                )
                maximum = max(
                    primary_receipt["max_abs_error"],
                    independent_receipt["max_abs_error"],
                )
                if maximum > amendment["unchanged_requirements"][
                    "real_source_maximum_absolute_error"
                ]:
                    raise RuntimeError("real source absolute check failed")
                comparisons.append(
                    {
                        "ordinal": ordinal,
                        "seed_sha256": seed_sha256,
                        "maximum_absolute_error": maximum,
                        "primary": primary_receipt,
                        "independent": independent_receipt,
                    }
                )
            real_rows.append(
                {
                    "artifact_id": target["artifact_id"],
                    "conv_node": target["conv_node"],
                    "batch_norm_node": target["batch_norm_node"],
                    "comparisons": comparisons,
                }
            )
            for ordinal in range(
                amendment["unseen_panel"]["ordinals"]["start_inclusive"],
                amendment["unseen_panel"]["ordinals"]["stop_exclusive"],
            ):
                panel_artifact_id = (
                    target["artifact_id"]
                    + ":A1-NUMERICAL-STABILITY-V1:"
                    + f"{ordinal:02d}"
                )
                panel_desc = dict(desc)
                panel_desc["artifact_id"] = panel_artifact_id
                primary = primary_lower(panel_desc)
                independent = independent_lower(
                    module,
                    panel_artifact_id,
                    target["conv_node"],
                    target["batch_norm_node"],
                )
                primary_bytes = (canonical(primary) + "\n").encode()
                if primary_bytes != (canonical(independent) + "\n").encode():
                    raise RuntimeError("panel lowerers disagree")
                if original_payload is None:
                    original_payload = primary
                artifact_path = (
                    directory
                    / f"{target['conv_node']}_{ordinal:02d}.json"
                )
                execution = v5_execute(
                    primary,
                    original,
                    base["grammar_extension"][
                        "new_structural_signature_sha256"
                    ],
                    artifact_path,
                )
                numerical = combined_tolerance_evaluate(
                    artifact_path,
                    primary,
                    absolute_tolerance=absolute,
                    relative_tolerance=relative,
                )
                if not numerical["combined_tolerance_passed"]:
                    raise RuntimeError(
                        "unseen synthetic panel combined tolerance failed"
                    )
                panel_rows.append(
                    {
                        "target_conv_node": target["conv_node"],
                        "replicate_ordinal": ordinal,
                        "panel_artifact_id_sha256": hashlib.sha256(
                            panel_artifact_id.encode()
                        ).hexdigest(),
                        "lowered_artifact_sha256": hashlib.sha256(
                            primary_bytes
                        ).hexdigest(),
                        "independent_artifact_byte_identical": True,
                        "v5_execution": execution,
                        "combined_numerical_evaluation": numerical,
                    }
                )
        if original_payload is None:
            raise RuntimeError("unseen panel was empty")
        hostile = hostile_batch(
            original_payload,
            original,
            base["grammar_extension"]["new_structural_signature_sha256"],
            directory,
        )
    payload = {
        "version": "FOUNDRY_A1_FOLD_NUMERICAL_STABILITY_WORKER_V1",
        "real_source_targets": real_rows,
        "unseen_panel": panel_rows,
        "hostile_rejections": hostile,
        "summary": {
            "real_targets": len(real_rows),
            "real_source_comparisons": sum(
                len(row["comparisons"]) for row in real_rows
            ),
            "maximum_real_source_absolute_error": max(
                item["maximum_absolute_error"]
                for row in real_rows
                for item in row["comparisons"]
            ),
            "unseen_panel_replicates": len(panel_rows),
            "unseen_panel_combined_passes": sum(
                row["combined_numerical_evaluation"][
                    "combined_tolerance_passed"
                ]
                for row in panel_rows
            ),
            "unseen_panel_byte_identical_lowerings": sum(
                row["independent_artifact_byte_identical"]
                for row in panel_rows
            ),
            "unseen_panel_original_plan_zero": sum(
                row["v5_execution"]["original_grammar_plan_index"] == 0
                for row in panel_rows
            ),
            "unseen_panel_adapted_plan_one": sum(
                row["v5_execution"]["adapted_grammar_plan_index"] == 1
                for row in panel_rows
            ),
            "unseen_panel_plan_sets_agree": sum(
                row["v5_execution"]["candidate_plan_count"] == 2
                and row["v5_execution"]["evaluator_plan_count"] == 2
                for row in panel_rows
            ),
            "maximum_panel_absolute_error": max(
                row["combined_numerical_evaluation"][
                    "maximum_absolute_error"
                ]
                for row in panel_rows
            ),
            "maximum_panel_excess": max(
                row["combined_numerical_evaluation"]["maximum_excess"]
                for row in panel_rows
            ),
            "hostile_cases": len(hostile),
            "hostile_rejections": len(hostile),
            "unsupported_or_failed_workloads": len(unsupported),
        },
        "preserved_phase146_failure_sha256": sha(
            HERE
            / amendment["trigger"]["preserved_failed_result"]["path"]
        ),
        "pristine_preregistration": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    WORKER_RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE147_WORKER"
        f" real={payload['summary']['real_source_comparisons']}"
        f" unseen={payload['summary']['unseen_panel_combined_passes']}"
        f"/{payload['summary']['unseen_panel_replicates']}"
        f" hostile={len(hostile)}/{len(hostile)}"
    )


def main() -> None:
    if "--worker" in sys.argv:
        worker()
        return
    amendment = json.loads(AMENDMENT.read_text())
    freeze = json.loads(FREEZE.read_text())
    providers_exact = all(
        sha(HERE / row["path"]) == row["sha256"]
        for row in amendment["provider_records"]
    )
    preserved = amendment["trigger"]["preserved_failed_result"]
    freeze_exact = (
        freeze["amendment_sha256"] == sha(AMENDMENT)
        and freeze["provider_records"] == amendment["provider_records"]
        and freeze["preserved_failed_result"] == preserved
        and freeze[
            "frozen_before_amended_runner_implementation_or_panel_execution"
        ]
        is True
        and freeze["pristine_preregistration"] is False
    )
    preserved_failure_exact = (
        sha(HERE / preserved["path"]) == preserved["sha256"]
        and json.loads((HERE / preserved["path"]).read_text())["status"]
        == preserved["status"]
    )
    limits = {
        "wall_limit_seconds": 240,
        "cpu_limit_seconds": 200,
        "rss_limit_kib": 4_500_000,
    }
    receipt = run_metered_tree(
        [str(pathlib.Path(sys.executable).resolve()), str(__file__), "--worker"],
        cwd=HERE,
        environment={
            "PYTHONHASHSEED": "0",
            "PYTHONWARNINGS": "ignore",
            "OMP_NUM_THREADS": "1",
            "MKL_NUM_THREADS": "1",
        },
        **limits,
    )
    natural = (
        receipt["returncode"] == 0
        and receipt["termination"] == "natural"
        and receipt["process_group_reaped"] is True
        and "FOUNDRY_PHASE147_WORKER" in receipt["stdout_text"]
    )
    observed = (
        json.loads(WORKER_RESULT.read_text())
        if natural and WORKER_RESULT.exists()
        else {}
    )
    summary = observed.get("summary", {})
    expected_panel = amendment["unseen_panel"]["total_replicates"]
    checks = {
        "amendment_freeze_and_providers_exact": providers_exact and freeze_exact,
        "preserved_phase146_failure_hash_exact": preserved_failure_exact,
        "metered_worker_terminated_naturally": natural,
        "resource_and_reaping_checks_pass": (
            natural
            and receipt["observed_process_count"] >= 1
            and receipt["peak_group_rss_kib"] > 0
            and receipt["rusage_user_cpu_ns"]
            + receipt["rusage_system_cpu_ns"]
            > 0
        ),
        "nine_real_source_absolute_checks_pass": (
            summary.get("real_targets") == 3
            and summary.get("real_source_comparisons") == 9
            and summary.get(
                "maximum_real_source_absolute_error", math.inf
            )
            <= amendment["unchanged_requirements"][
                "real_source_maximum_absolute_error"
            ]
        ),
        "forty_eight_unseen_combined_tolerance_checks_pass": (
            summary.get("unseen_panel_replicates") == expected_panel
            and summary.get("unseen_panel_combined_passes") == expected_panel
            and summary.get("maximum_panel_excess", math.inf) == 0.0
        ),
        "all_48_primary_and_independent_lowerings_byte_identical": (
            summary.get("unseen_panel_byte_identical_lowerings")
            == expected_panel
        ),
        "all_48_strict_v5_artifacts_and_nonreference_plans_execute": (
            len(observed.get("unseen_panel", [])) == expected_panel
            and all(
                row["v5_execution"]["metrics"]["layouts_valid"] is True
                for row in observed.get("unseen_panel", [])
            )
        ),
        "all_48_candidate_and_evaluator_plan_sets_agree": (
            summary.get("unseen_panel_plan_sets_agree") == expected_panel
        ),
        "all_48_original_plan_zero_and_adapted_plan_one": (
            summary.get("unseen_panel_original_plan_zero") == expected_panel
            and summary.get("unseen_panel_adapted_plan_one") == expected_panel
        ),
        "twelve_hostile_cases_rejected": (
            summary.get("hostile_cases") == 12
            and summary.get("hostile_rejections") == 12
        ),
        "validation_v6_unread": observed.get("validation_v6_accessed") is False,
    }
    operationally_valid = all(checks.values())
    payload = {
        "version": "FOUNDRY_A1_FOLD_NUMERICAL_STABILITY_RESULT_V1",
        "status": (
            "A1_POST_FAILURE_NUMERICAL_REMEDIATION_PASS"
            if operationally_valid
            else "A1_POST_FAILURE_NUMERICAL_REMEDIATION_INVALID"
        ),
        "amendment_sha256": sha(AMENDMENT),
        "freeze_sha256": sha(FREEZE),
        "preserved_failed_result": preserved,
        "pristine_preregistration": False,
        "runner_records": [
            {
                "path": pathlib.Path(__file__).name,
                "sha256": sha(pathlib.Path(__file__)),
            },
            {
                "path": "phase146_a1_pattern_first_fold_conformance.py",
                "sha256": sha(
                    HERE / "phase146_a1_pattern_first_fold_conformance.py"
                ),
            },
        ],
        "limits": limits,
        "receipt": receipt,
        "checks": checks,
        "operationally_valid": operationally_valid,
        "observed": observed,
        "decision": {
            "A1_numerical_remediation_passed": operationally_valid,
            "phase146_remains_failed": True,
            "next_route": (
                "prefreeze and execute full 23-graph A1 runtime contract batch"
                if operationally_valid
                else "redesign A1 numerical semantics without production mount"
            ),
            "A1_production_integrated": False,
            "production_integrated_arms": 7,
        },
        "claim_boundary": amendment["claim_boundary"],
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE147_A1_NUMERICAL_REMEDIATION"
        f" status={payload['status']}"
        f" real={summary.get('real_source_comparisons', 0)}"
        f" unseen={summary.get('unseen_panel_combined_passes', 0)}"
        f"/{expected_panel}"
        " phase146=FAILED integrated=7/10 prospective=false"
    )
    if not operationally_valid:
        raise RuntimeError(
            "A1 numerical remediation invalid: "
            + canonical(
                {
                    "failed": [
                        key for key, value in checks.items() if not value
                    ],
                    "stderr": receipt["stderr_text"],
                }
            )
        )


if __name__ == "__main__":
    main()
