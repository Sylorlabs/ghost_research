#!/usr/bin/env python3
"""Execute the pre-frozen Enumo tensor-domain feasibility protocol."""

from __future__ import annotations

import hashlib
import json
import os
import pathlib
import tempfile

from enumo_tensor_rule_verifier import (
    hostile_parser_selftest,
    verify_rules,
)
from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/ENUMO_TENSOR_DOMAIN_FEASIBILITY_PROTOCOL_V1.json"
)
FREEZE = HERE / "results/enumo_tensor_feasibility_v1_freeze.json"
RESULT = HERE / "results/phase132_enumo_tensor_domain_feasibility.json"
CRATE = HERE / "external_controls/enumo/tensor_feasibility"
USER_CARGO = pathlib.Path.home() / ".cargo"
USER_RUSTUP = pathlib.Path.home() / ".rustup"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def exact_provider_records(protocol: dict[str, object]) -> list[dict[str, str]]:
    records = protocol["provider_records"]
    if not isinstance(records, list):
        raise RuntimeError("provider records malformed")
    for row in records:
        if not isinstance(row, dict):
            raise RuntimeError("provider record malformed")
        path = HERE / str(row["path"])
        if sha(path) != row["sha256"]:
            raise RuntimeError(f"provider mismatch: {row['path']}")
    return records


def cargo_environment(cargo_home: pathlib.Path) -> dict[str, str]:
    return {
        "CARGO_HOME": str(cargo_home),
        "CARGO_NET_OFFLINE": "true",
        "RUSTUP_HOME": str(USER_RUSTUP),
        "PATH": f"{USER_CARGO / 'bin'}:/usr/bin:/bin",
        "RUST_BACKTRACE": "0",
    }


def last_json_line(stdout: str) -> dict[str, object]:
    for line in reversed(stdout.splitlines()):
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            return value
    raise RuntimeError("runner emitted no JSON object")


def natural(receipt: dict[str, object]) -> bool:
    return (
        receipt["returncode"] == 0
        and receipt["termination"] == "natural"
        and receipt["process_group_reaped"] is True
    )


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    providers = exact_provider_records(protocol)
    protocol_and_freeze_exact = (
        freeze["protocol_sha256"] == sha(PROTOCOL)
        and freeze["provider_records"] == providers
        and freeze["frozen_before_runner_implementation_or_execution"] is True
        and freeze["experiment_name"] == "ENUMO_TENSOR_DOMAIN_FEASIBILITY"
        and freeze["is_frozen_boolean_A7"] is False
        and freeze["may_promote_A7"] is False
        and freeze["may_increase_production_integrated_arm_count"] is False
        and freeze["validation_v6_accessed"] is False
    )
    if not protocol_and_freeze_exact:
        raise RuntimeError("pre-execution freeze is not exact")

    cargo = USER_CARGO / "bin/cargo"
    with tempfile.TemporaryDirectory(
        prefix="foundry-enumo-tensor-cargo.", dir="/tmp"
    ) as temporary:
        cargo_home = pathlib.Path(temporary)
        registry = cargo_home / "registry"
        registry.mkdir()
        (registry / "src").mkdir()
        os.symlink(USER_CARGO / "registry/cache", registry / "cache")
        os.symlink(USER_CARGO / "registry/index", registry / "index")
        target = cargo_home / "target"
        environment = cargo_environment(cargo_home)
        build_limits = {
            "wall_limit_seconds": 240,
            "cpu_limit_seconds": 220,
            "rss_limit_kib": 2_500_000,
        }
        build = run_metered_tree(
            [
                str(cargo),
                "build",
                "--release",
                "--offline",
                "--locked",
                "--target-dir",
                str(target),
            ],
            cwd=CRATE,
            environment=environment,
            **build_limits,
        )
        binary = target / "release/foundry-enumo-tensor-feasibility"
        run_limits = {
            "wall_limit_seconds": 180,
            "cpu_limit_seconds": 160,
            "rss_limit_kib": 2_000_000,
        }
        if natural(build) and binary.is_file():
            execution = run_metered_tree(
                [str(binary.resolve())],
                cwd=CRATE,
                environment={
                    "PATH": "/usr/bin:/bin",
                    "RUST_BACKTRACE": "0",
                },
                **run_limits,
            )
            output = (
                last_json_line(str(execution["stdout_text"]))
                if natural(execution)
                else {}
            )
            binary_sha256 = sha(binary)
        else:
            execution = {
                "version": "FOUNDRY_RESOURCE_RECEIPT_V2_NOT_RUN",
                "reason": "source build did not terminate naturally",
            }
            output = {}
            binary_sha256 = None

    learned = output.get("learned_rules", [])
    if not isinstance(learned, list) or not all(
        isinstance(rule, str) for rule in learned
    ):
        learned = []
    hostile = hostile_parser_selftest()
    independent = verify_rules(
        learned, tuple(protocol["acceptance"]["independent_expanded_scalar_domain"])
    )
    stage_counts = output.get("stage_rule_counts", [])
    workload_counts = output.get("workload_counts", [])
    checks = {
        "preexecution_protocol_and_freeze_exact": protocol_and_freeze_exact,
        "upstream_provider_hashes_match": len(providers) == 9,
        "source_build_terminated_naturally": natural(build),
        "source_run_terminated_naturally": (
            isinstance(execution, dict)
            and execution.get("version") == "FOUNDRY_RESOURCE_RECEIPT_V2"
            and natural(execution)
        ),
        "stage_workloads_nonempty": (
            workload_counts
            and len(workload_counts) == 2
            and all(isinstance(count, int) and count > 0 for count in workload_counts)
        ),
        "learned_rules_nonempty": len(learned) > 0,
        "stage_rule_counts_reported": (
            isinstance(stage_counts, list)
            and len(stage_counts) == 2
            and all(isinstance(count, int) and count >= 0 for count in stage_counts)
        ),
        "every_rule_primary_valid": (
            output.get("all_rules_primary_valid") is True
        ),
        "independent_parser_rejects_hostile_rules": hostile["all_rejected"],
        "every_rule_independently_expanded_valid": (
            independent["rules_checked"] == len(learned)
            and independent["all_rules_passed"] is True
            and len(learned) > 0
        ),
        "build_process_tree_accounted_and_reaped": (
            natural(build)
            and build["observed_process_count"] >= 2
            and build["peak_group_rss_kib"] > 0
            and build["rusage_user_cpu_ns"] + build["rusage_system_cpu_ns"] > 0
        ),
        "run_process_tree_accounted_and_reaped": (
            isinstance(execution, dict)
            and execution.get("version") == "FOUNDRY_RESOURCE_RECEIPT_V2"
            and natural(execution)
            and execution["observed_process_count"] >= 1
            and execution["peak_group_rss_kib"] > 0
            and execution["rusage_user_cpu_ns"]
            + execution["rusage_system_cpu_ns"]
            > 0
        ),
        "separate_identity_preserved": (
            output.get("experiment_name")
            == "ENUMO_TENSOR_DOMAIN_FEASIBILITY"
            and output.get("evaluator_authored_domain") is True
            and output.get("is_frozen_boolean_a7") is False
        ),
        "validation_v6_unread": (
            output.get("validation_v6_accessed") is False
            and protocol["claim_boundary"][
                "validation_v6_source_runtime_graph_or_outcome_accessed"
            ]
            is False
        ),
    }
    passed = all(checks.values())
    payload = {
        "version": "FOUNDRY_ENUMO_TENSOR_DOMAIN_FEASIBILITY_RESULT_V1",
        "status": (
            "ENUMO_TENSOR_DOMAIN_FEASIBILITY_PASS"
            if passed
            else "ENUMO_TENSOR_DOMAIN_FEASIBILITY_NOT_ESTABLISHED"
        ),
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "provider_records": providers,
        "runner_records": [
            {
                "path": str(path.relative_to(HERE)),
                "sha256": sha(path),
            }
            for path in (
                CRATE / "Cargo.toml",
                CRATE / "Cargo.lock",
                CRATE / "src/main.rs",
                HERE / "enumo_tensor_rule_verifier.py",
            )
        ],
        "binary_sha256": binary_sha256,
        "limits": {"build": build_limits, "run": run_limits},
        "receipts": {"build": build, "run": execution},
        "observed": output,
        "hostile_parser_selftest": hostile,
        "independent_expanded_validation": independent,
        "checks": checks,
        "claim_boundary": {
            "calibration_only": True,
            "evaluator_authored_domain": True,
            "full_tensor_graph_language": False,
            "full_23_graph_adapter": False,
            "is_frozen_boolean_A7": False,
            "A7_production_integrated": False,
            "production_integrated_arms": 6,
            "P1_advance": False,
            "P3_integration_advance": False,
            "validation_v6_accessed": False,
            "prospective_trial_authorized": False,
        },
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE132_ENUMO_TENSOR_FEASIBILITY"
        f" status={payload['status']}"
        f" workloads={workload_counts}"
        f" stages={stage_counts}"
        f" rules={len(learned)}"
        f" hostile={hostile['rejected_cases']}/{hostile['hostile_cases']}"
        f" integrated=6/10 prospective=false"
    )


if __name__ == "__main__":
    main()
