#!/usr/bin/env python3
"""Execute the frozen adapted A1 pattern-first fold conformance phase."""

from __future__ import annotations

import copy
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
    verify_extension,
    v5_execute,
)
from independent_a1_fold_lowering import (
    compare as independent_compare,
    lower as independent_lower,
)
from independent_framework_runtime import clone_tree, primary_compare
from phase63_pareto_motif_calibration import workloads
from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "arm_adapter_fixtures/A1_PATTERN_FIRST_FOLD_PROTOCOL_V1.json"
FREEZE = HERE / "results/a1_pattern_first_fold_v1_freeze.json"
GRAMMAR = HERE / "../operator_v5_1/results/frozen_grammar_v5_1.json"
WORKER_RESULT = HERE / "results/phase146_a1_pattern_first_fold_worker.json"
RESULT = HERE / "results/phase146_a1_pattern_first_fold_conformance.json"

OPERATOR = (HERE / "../operator_v5").resolve()
if str(OPERATOR) not in sys.path:
    sys.path.insert(0, str(OPERATOR))

from ghost_operator_candidate_v5 import enumerate_plans as candidate_enumerate  # noqa: E402
from ghost_operator_core_v5 import (  # noqa: E402
    canonical_json,
    load_artifact,
    load_plan_text,
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


def validate_artifact(payload: dict[str, object], path: pathlib.Path) -> None:
    path.write_text(canonical_json(payload) + "\n")
    parsed, _ = load_artifact(path)
    primary = candidate_enumerate(payload)
    independent = evaluator_enumerate(parsed)
    if canonical(primary) != canonical(independent):
        raise ValueError("plan enumerators disagree")
    for plan in primary:
        load_plan_text(canonical_json(plan), parsed)


def hostile_batch(
    valid: dict[str, object],
    original: dict[str, Any],
    signature: str,
    directory: pathlib.Path,
) -> list[dict[str, str]]:
    artifact_mutations: list[tuple[str, Any]] = [
        (
            "artifact_version",
            lambda item: item.__setitem__(
                "version", "GHOST_OPERATOR_ARTIFACT_V999"
            ),
        ),
        (
            "input_dtype",
            lambda item: item["inputs"][0]["type"].__setitem__(
                "dtype", "float64"
            ),
        ),
        (
            "input_storage",
            lambda item: item["inputs"][0]["type"].__setitem__(
                "storage", "opaque"
            ),
        ),
        (
            "input_seed",
            lambda item: item["inputs"][0].__setitem__(
                "seed_hex", "not-a-seed"
            ),
        ),
        (
            "reuse_calls",
            lambda item: item.__setitem__("reuse_calls", 0),
        ),
        (
            "duplicate_node_id",
            lambda item: item["reference_program"]["nodes"][8].__setitem__(
                "id", "n7"
            ),
        ),
        (
            "zero_conv_groups",
            lambda item: item["reference_program"]["nodes"][7]["attrs"].__setitem__(
                "groups", 0
            ),
        ),
        (
            "missing_epsilon_constant",
            lambda item: item["constants"].__delitem__("c0"),
        ),
    ]
    records: list[dict[str, str]] = []
    for index, (name, mutate) in enumerate(artifact_mutations):
        item = copy.deepcopy(valid)
        mutate(item)
        try:
            validate_artifact(item, directory / f"hostile_{index}.json")
        except Exception as exc:
            records.append(
                {
                    "case": name,
                    "surface": "typed_artifact",
                    "rejection": type(exc).__name__,
                }
            )
        else:
            raise RuntimeError(f"hostile artifact accepted: {name}")

    valid_extension = copy.deepcopy(original)
    valid_extension["rules"][signature] = {"kind": "leaf", "plan_index": 1}
    grammar_mutations: list[tuple[str, Any]] = [
        (
            "extension_selects_reference",
            lambda item: item["rules"].__setitem__(
                signature, {"kind": "leaf", "plan_index": 0}
            ),
        ),
        (
            "extension_adds_extra_signature",
            lambda item: item["rules"].__setitem__(
                "f" * 64, {"kind": "leaf", "plan_index": 1}
            ),
        ),
        (
            "extension_overwrites_original_rule",
            lambda item: item["rules"].__setitem__(
                next(iter(original["rules"])),
                {"kind": "leaf", "plan_index": 999},
            ),
        ),
        (
            "extension_changes_version",
            lambda item: item.__setitem__("version", "altered"),
        ),
    ]
    for name, mutate in grammar_mutations:
        item = copy.deepcopy(valid_extension)
        mutate(item)
        try:
            verify_extension(original, item, signature)
        except Exception as exc:
            records.append(
                {
                    "case": name,
                    "surface": "grammar_extension",
                    "rejection": type(exc).__name__,
                }
            )
        else:
            raise RuntimeError(f"hostile grammar accepted: {name}")
    return records


def worker() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    original = json.loads(GRAMMAR.read_text())
    targets = protocol["targets"]
    target_artifact = targets[0]["artifact_id"]
    instantiated, unsupported = workloads()
    selected = [
        workload
        for suite, workload in instantiated
        if f"{suite}:{workload['family']}" == target_artifact
    ]
    if len(selected) != 1:
        raise RuntimeError("frozen source artifact is not unique")
    workload = selected[0]
    exported = torch.export.export(
        workload["model"],
        workload["args"],
        workload["kwargs"],
        strict=True,
    )
    module = exported.module()
    expected_targets = [
        (
            row["artifact_id"],
            row["conv_node"],
            row["batch_norm_node"],
        )
        for row in targets
    ]
    if any(artifact_id != target_artifact for artifact_id, _, _ in expected_targets):
        raise RuntimeError("protocol target artifact changed")
    target_rows = []
    with tempfile.TemporaryDirectory(prefix="foundry-a1-fold-") as raw_dir:
        directory = pathlib.Path(raw_dir)
        for artifact_id, conv_name, batch_name in expected_targets:
            desc = descriptor(module, artifact_id, conv_name, batch_name)
            primary = primary_lower(desc)
            independent = independent_lower(
                module, artifact_id, conv_name, batch_name
            )
            primary_bytes = (canonical(primary) + "\n").encode()
            independent_bytes = (canonical(independent) + "\n").encode()
            if primary_bytes != independent_bytes:
                raise RuntimeError("primary and independent artifacts differ")
            comparisons = []
            for ordinal in range(
                protocol["actual_value_verification"][
                    "invocations_per_target"
                ]
            ):
                seed, seed_sha256 = invocation_seed(
                    artifact_id, conv_name, ordinal
                )
                generator = torch.Generator(device="cpu").manual_seed(seed)
                args = randomized(workload["args"], generator)
                kwargs = randomized(workload["kwargs"], generator)
                values = capture(module, args, kwargs)
                expected = values[batch_name][0]
                actual = folded_actual(desc, values)
                primary_receipt = primary_compare(expected, actual)
                independent_receipt = independent_compare(
                    expected,
                    actual,
                    values[desc["x"].name],
                    tolerance=protocol["actual_value_verification"][
                        "maximum_absolute_error"
                    ],
                )
                maximum = max(
                    primary_receipt["max_abs_error"],
                    independent_receipt["max_abs_error"],
                )
                if (
                    not math.isfinite(maximum)
                    or maximum
                    > protocol["actual_value_verification"][
                        "maximum_absolute_error"
                    ]
                ):
                    raise RuntimeError("actual source comparison exceeded tolerance")
                comparisons.append(
                    {
                        "ordinal": ordinal,
                        "seed_sha256": seed_sha256,
                        "primary": primary_receipt,
                        "independent": independent_receipt,
                    }
                )
            execution = v5_execute(
                primary,
                original,
                protocol["grammar_extension"][
                    "new_structural_signature_sha256"
                ],
                directory / f"{conv_name}.json",
            )
            if (
                execution["metrics"]["max_abs_error"]
                > protocol["v5_execution"][
                    "nonreference_maximum_absolute_error"
                ]
                or execution["metrics"]["compiled_max_abs_error"]
                > protocol["v5_execution"][
                    "nonreference_compiled_maximum_absolute_error"
                ]
            ):
                raise RuntimeError("v5 nonreference plan exceeded tolerance")
            target_rows.append(
                {
                    "artifact_id": artifact_id,
                    "conv_node": conv_name,
                    "batch_norm_node": batch_name,
                    "lowered_artifact_sha256": hashlib.sha256(
                        primary_bytes
                    ).hexdigest(),
                    "independent_artifact_byte_identical": True,
                    "actual_value_comparisons": comparisons,
                    "v5_execution": execution,
                }
            )
        hostile = hostile_batch(
            primary_lower(
                descriptor(
                    module,
                    expected_targets[0][0],
                    expected_targets[0][1],
                    expected_targets[0][2],
                )
            ),
            original,
            protocol["grammar_extension"][
                "new_structural_signature_sha256"
            ],
            directory,
        )
    payload = {
        "version": "FOUNDRY_A1_PATTERN_FIRST_FOLD_WORKER_V1",
        "targets": target_rows,
        "summary": {
            "targets": len(target_rows),
            "actual_value_comparisons": sum(
                len(row["actual_value_comparisons"]) for row in target_rows
            ),
            "byte_identical_independent_artifacts": sum(
                row["independent_artifact_byte_identical"]
                for row in target_rows
            ),
            "strict_v5_artifacts": len(target_rows),
            "candidate_plan_sets": len(target_rows),
            "evaluator_plan_sets": len(target_rows),
            "original_plan_zero_selections": sum(
                row["v5_execution"]["original_grammar_plan_index"] == 0
                for row in target_rows
            ),
            "adapted_plan_one_selections": sum(
                row["v5_execution"]["adapted_grammar_plan_index"] == 1
                for row in target_rows
            ),
            "nonreference_measurements": len(target_rows),
            "maximum_actual_value_error": max(
                comparison["primary"]["max_abs_error"]
                for row in target_rows
                for comparison in row["actual_value_comparisons"]
            ),
            "maximum_v5_error": max(
                row["v5_execution"]["metrics"]["max_abs_error"]
                for row in target_rows
            ),
            "hostile_cases": len(hostile),
            "hostile_rejections": len(hostile),
            "unsupported_or_failed_workloads": len(unsupported),
        },
        "hostile_rejections": hostile,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    WORKER_RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE146_WORKER"
        f" targets={len(target_rows)}"
        f" comparisons={payload['summary']['actual_value_comparisons']}"
        f" hostile={len(hostile)}/{len(hostile)}"
    )


def main() -> None:
    if "--worker" in sys.argv:
        worker()
        return
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    providers_exact = all(
        sha(HERE / row["path"]) == row["sha256"]
        for row in protocol["provider_records"]
    )
    freeze_exact = (
        freeze["protocol_sha256"] == sha(PROTOCOL)
        and freeze["provider_records"] == protocol["provider_records"]
        and freeze["targets"] == protocol["targets"]
        and freeze["new_structural_signature_sha256"]
        == protocol["grammar_extension"][
            "new_structural_signature_sha256"
        ]
        and freeze["frozen_before_lowerer_implementation_or_execution"] is True
    )
    limits = {
        "wall_limit_seconds": 120,
        "cpu_limit_seconds": 100,
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
        and "FOUNDRY_PHASE146_WORKER" in receipt["stdout_text"]
    )
    observed = (
        json.loads(WORKER_RESULT.read_text())
        if natural and WORKER_RESULT.exists()
        else {}
    )
    summary = observed.get("summary", {})
    checks = {
        "protocol_freeze_and_providers_exact": providers_exact and freeze_exact,
        "metered_worker_terminated_naturally": natural,
        "process_tree_cpu_rss_wall_and_reaping_accounted": (
            natural
            and receipt["observed_process_count"] >= 1
            and receipt["peak_group_rss_kib"] > 0
            and receipt["rusage_user_cpu_ns"]
            + receipt["rusage_system_cpu_ns"]
            > 0
        ),
        "all_three_targets_exact": summary.get("targets") == 3,
        "nine_actual_value_comparisons_pass": (
            summary.get("actual_value_comparisons") == 9
            and summary.get("maximum_actual_value_error", math.inf)
            <= protocol["actual_value_verification"][
                "maximum_absolute_error"
            ]
        ),
        "three_byte_identical_independent_artifacts": (
            summary.get("byte_identical_independent_artifacts") == 3
        ),
        "three_strict_v5_artifacts_pass": (
            summary.get("strict_v5_artifacts") == 3
        ),
        "all_six_enumerated_plan_sets_agree": (
            summary.get("candidate_plan_sets") == 3
            and summary.get("evaluator_plan_sets") == 3
            and all(
                row["v5_execution"]["candidate_plan_count"] == 2
                and row["v5_execution"]["evaluator_plan_count"] == 2
                for row in observed.get("targets", [])
            )
        ),
        "three_original_grammar_plan_zero_selections": (
            summary.get("original_plan_zero_selections") == 3
        ),
        "three_adapted_grammar_plan_one_selections": (
            summary.get("adapted_plan_one_selections") == 3
        ),
        "three_nonreference_v5_measurements_pass": (
            summary.get("nonreference_measurements") == 3
            and summary.get("maximum_v5_error", math.inf)
            <= protocol["v5_execution"][
                "nonreference_maximum_absolute_error"
            ]
        ),
        "twelve_hostile_cases_rejected": (
            summary.get("hostile_cases") == 12
            and summary.get("hostile_rejections") == 12
        ),
        "validation_v6_unread": observed.get("validation_v6_accessed") is False,
    }
    operationally_valid = all(checks.values())
    payload = {
        "version": "FOUNDRY_A1_PATTERN_FIRST_FOLD_RESULT_V1",
        "status": (
            "A1_ADAPTED_FOLD_CONFORMANCE_PASS"
            if operationally_valid
            else "A1_ADAPTED_FOLD_CONFORMANCE_INVALID"
        ),
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "runner_records": [
            {
                "path": pathlib.Path(__file__).name,
                "sha256": sha(pathlib.Path(__file__)),
            },
            {
                "path": "a1_pattern_first_fold.py",
                "sha256": sha(HERE / "a1_pattern_first_fold.py"),
            },
            {
                "path": "independent_a1_fold_lowering.py",
                "sha256": sha(HERE / "independent_a1_fold_lowering.py"),
            },
        ],
        "limits": limits,
        "receipt": receipt,
        "checks": checks,
        "operationally_valid": operationally_valid,
        "observed": observed,
        "decision": {
            "A1_conformance_passed": operationally_valid,
            "next_route": (
                "mount adapted A1 over the full 23-graph contract batch"
                if operationally_valid
                else "remediate failed A1 conformance gate"
            ),
            "A1_production_integrated": False,
            "production_integrated_arms": 7,
        },
        "claim_boundary": {
            "adapted_not_unchanged_v5_1_grammar": True,
            "one_new_calibration_signature_only": True,
            "existing_constructor_semantics_only": True,
            "not_heldout_transfer": True,
            "not_production_integration_until_contract_batch": True,
            "validation_v6_accessed": False,
            "prospective_trial_authorized": False,
        },
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE146_A1_PATTERN_FIRST_FOLD"
        f" status={payload['status']}"
        f" comparisons={summary.get('actual_value_comparisons', 0)}"
        f" hostile={summary.get('hostile_rejections', 0)}/12"
        " integrated=7/10 prospective=false"
    )
    if not operationally_valid:
        raise RuntimeError(
            "A1 pattern-first conformance invalid: "
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
