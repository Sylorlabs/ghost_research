#!/usr/bin/env python3
"""Read-only representative arms for integrated resource-meter validation."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))


def forge_arm() -> None:
    from run_calibration import TRAIN, _select_tool

    tool, receipt = _select_tool("declarations", TRAIN["declarations"])
    print(
        "METERED_FORGE_PASS"
        f" digest={tool['tool_digest']} proposals={receipt['proposal_count']}"
    )


def fixed_arm() -> None:
    from run_calibration import PHASE2, _evaluate_phase, _fixed_tools

    result = _evaluate_phase(_fixed_tools(), PHASE2, "metered_fixed_read_only")
    summary = result["summary"]
    if summary["candidate_exact"] != summary["tasks"]:
        raise RuntimeError("fixed arm no longer passes")
    print(f"METERED_FIXED_PASS tasks={summary['tasks']}")


def verifier_arm() -> None:
    from independent_evaluator import hostile_selftest

    print(f"METERED_VERIFIER_PASS rejected={hostile_selftest()}")


def compiler_arm() -> None:
    v5 = ROOT / "ghost_scientist/operator_v5"
    v51 = ROOT / "ghost_scientist/operator_v5_1"
    sys.path.insert(0, str(v5))
    from ghost_operator_core_v5 import TensorProgramModule, load_artifact, load_plan_text, materialize_inputs
    import torch

    artifact_path = v51 / "results/heldout_corpus/artifacts/heldout_v5_1_000.json"
    plan_path = v51 / "results/heldout_trial/candidate_plans/heldout_v5_1_000.json"
    artifact, _ = load_artifact(artifact_path)
    plan = load_plan_text(plan_path.read_text(encoding="utf-8"), artifact)
    module, _ = TensorProgramModule.build(artifact, plan)
    compiled = torch.compile(module, backend="inductor", fullgraph=True)
    with torch.no_grad():
        output = compiled(*materialize_inputs(artifact))
    tensors = output if isinstance(output, tuple) else (output,)
    # Explicitly close compiler workers so the resource ledger covers a
    # bounded process tree rather than relying on interpreter-exit cleanup.
    from torch._inductor.async_compile import shutdown_compile_workers

    shutdown_compile_workers()
    print(f"METERED_COMPILER_PASS outputs={len(tensors)}")


def corpus_arm() -> None:
    import torch
    from torch._export.db.case import SupportLevel
    from torch._export.db.examples import all_examples

    completed = 0
    for _name, case in sorted(all_examples().items()):
        if case.support_level != SupportLevel.SUPPORTED:
            continue
        kwargs = {}
        if getattr(case, "dynamic_shapes", None) is not None:
            kwargs["dynamic_shapes"] = case.dynamic_shapes
        torch.export.export(case.model, case.example_args, case.example_kwargs or {}, **kwargs)
        completed += 1
        if completed == 4:
            break
    print(f"METERED_CORPUS_PASS exports={completed}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "arm", choices=("forge", "fixed", "verifier", "compiler", "corpus")
    )
    arm = parser.parse_args().arm
    {
        "forge": forge_arm,
        "fixed": fixed_arm,
        "verifier": verifier_arm,
        "compiler": compiler_arm,
        "corpus": corpus_arm,
    }[arm]()


if __name__ == "__main__":
    main()
