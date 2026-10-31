#!/usr/bin/env python3
"""Phase 12: metered native-dedup audit for every newly forged tensor tool."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import sys
from typing import Any


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
V5 = ROOT / "ghost_scientist/operator_v5"
RESULTS = HERE / "results"
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(V5))

from ghost_operator_core_v5 import (  # noqa: E402
    TensorProgramModule,
    canonical_json,
    load_artifact,
    materialize_inputs,
    reference_plan,
)
from independent_tensor_tool_evaluator import (  # noqa: E402
    parse_library_bytes,
    render_plan,
    tool_matches,
)
from resource_meter_v2 import run_metered_tree  # noqa: E402


def normalize_inductor(code: str) -> str:
    code = re.sub(r"/[^\n'\" ]+/(?:torchinductor|tmp)[^\n'\" ]*", "<PATH>", code)
    code = re.sub(r"\b[a-f0-9]{32,64}\b", "<HASH>", code)
    code = re.sub(r"\bc[0-9a-f]{8,}\b", "<CONST>", code)
    code = re.sub(r"(?m)^#.*$", "", code)
    return "\n".join(line.rstrip() for line in code.splitlines() if line.strip())


def sha_text(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def representative(tool: dict[str, Any]):
    for corpus_name in ("prefreeze_corpus", "confirmation_corpus"):
        for path in sorted(
            (V5 / "results" / corpus_name / "artifacts").glob("*.json")
        ):
            artifact, raw = load_artifact(path)
            if tool_matches(tool, artifact):
                return corpus_name, path, artifact, raw
    raise RuntimeError(f"no representative for {tool['tool_id']}")


def compile_module(module, inputs) -> tuple[str | None, str | None]:
    import torch
    from torch._inductor.utils import run_and_get_code

    try:
        compiled = torch.compile(module, backend="inductor", fullgraph=True)
        _output, codes = run_and_get_code(compiled, *inputs)
        normalized = "\n".join(normalize_inductor(code) for code in codes)
        return sha_text(normalized), None
    except Exception as exc:
        return None, f"{type(exc).__name__}:{str(exc)[:240]}"


def worker(index: int) -> None:
    library = parse_library_bytes((RESULTS / "forged_tensor_tools.json").read_bytes())
    if not 0 <= index < len(library["tools"]):
        raise RuntimeError("tool index out of range")
    tool = library["tools"][index]
    corpus_name, path, artifact, raw = representative(tool)
    candidate_plan = render_plan(tool, artifact)
    inputs = materialize_inputs(artifact)
    candidate, _ = TensorProgramModule.build(artifact, candidate_plan)
    stock, _ = TensorProgramModule.build(artifact, reference_plan(artifact))
    candidate_digest, candidate_error = compile_module(candidate, inputs)
    stock_digest, stock_error = compile_module(stock, inputs)
    try:
        from torch._inductor.async_compile import shutdown_compile_workers

        shutdown_compile_workers()
    except Exception:
        pass
    duplicate = (
        candidate_digest is not None
        and stock_digest is not None
        and candidate_digest == stock_digest
    )
    required_unsupported = (
        candidate_error is not None
        and stock_error is not None
        and "does not support sparse Tensors" in candidate_error
        and "does not support sparse Tensors" in stock_error
    )
    if duplicate:
        decision = "REJECT_NATIVE_DUPLICATE"
    elif required_unsupported:
        decision = "QUARANTINE_REQUIRED_UNSUPPORTED"
    else:
        decision = "QUARANTINE_NONIDENTICAL"
    print(
        canonical_json(
            {
                "status": "FOUNDRY_TENSOR_NATIVE_WORKER_PASS",
                "tool_id": tool["tool_id"],
                "corpus": corpus_name,
                "opaque_id": artifact.opaque_id,
                "artifact_sha256": hashlib.sha256(raw).hexdigest(),
                "artifact_path_sha256": sha_text(str(path.resolve())),
                "candidate_plan_sha256": sha_text(canonical_json(candidate_plan)),
                "candidate_inductor_sha256": candidate_digest,
                "stock_inductor_sha256": stock_digest,
                "candidate_error": candidate_error,
                "stock_error": stock_error,
                "normalized_inductor_duplicate": duplicate,
                "required_unsupported": required_unsupported,
                "decision": decision,
            }
        )
    )


def parse_worker_output(receipt: dict[str, object]) -> dict[str, Any]:
    lines = str(receipt["stdout_text"]).splitlines()
    rows = [json.loads(line) for line in lines if line.startswith("{")]
    if len(rows) != 1 or rows[0].get("status") != "FOUNDRY_TENSOR_NATIVE_WORKER_PASS":
        raise RuntimeError(f"native worker did not emit one receipt: {lines}")
    return rows[0]


def orchestrate() -> None:
    from freeze_foundry_1 import verify

    verify()
    library_raw = (RESULTS / "forged_tensor_tools.json").read_bytes()
    library = parse_library_bytes(library_raw)
    python = pathlib.Path(sys.executable).resolve()
    environment = {
        "TORCHINDUCTOR_COMPILE_THREADS": "1",
        "OMP_NUM_THREADS": "1",
        "MKL_NUM_THREADS": "1",
    }
    compiler_receipts = []
    rows = []
    for index in range(len(library["tools"])):
        receipt = run_metered_tree(
            [str(python), str(pathlib.Path(__file__).resolve()), "--worker", str(index)],
            cwd=ROOT,
            wall_limit_seconds=120,
            cpu_limit_seconds=100,
            rss_limit_kib=4_000_000,
            environment=environment,
        )
        if (
            receipt["returncode"] != 0
            or receipt["termination"] != "natural"
            or not receipt["process_group_reaped"]
        ):
            raise RuntimeError(f"metered compiler worker failed: {receipt}")
        rows.append(parse_worker_output(receipt))
        compiler_receipts.append(receipt)

    component_arms = {}
    for name, script, marker in (
        (
            "tensor_forge",
            "phase10_tensor_tool_forge.py",
            "FOUNDRY_PHASE10_TENSOR_FORGE_PASS",
        ),
        (
            "independent_tensor_evaluator",
            "independent_tensor_tool_evaluator.py",
            "FOUNDRY_PHASE11_INDEPENDENT_TENSOR_EVAL_PASS",
        ),
    ):
        receipt = run_metered_tree(
            [str(python), str(HERE / script)],
            cwd=HERE,
            wall_limit_seconds=60,
            cpu_limit_seconds=45,
            rss_limit_kib=2_000_000,
            environment=environment,
        )
        receipt["expected_status_seen"] = marker in receipt["stdout_text"]
        component_arms[name] = receipt
    all_receipts = compiler_receipts + list(component_arms.values())
    gates = {
        "all_tools_classified": len(rows) == len(library["tools"]),
        "no_unclassified_decisions": all(
            row["decision"]
            in {
                "REJECT_NATIVE_DUPLICATE",
                "QUARANTINE_REQUIRED_UNSUPPORTED",
                "QUARANTINE_NONIDENTICAL",
            }
            for row in rows
        ),
        "all_arms_natural": all(
            item["returncode"] == 0 and item["termination"] == "natural"
            for item in all_receipts
        ),
        "all_groups_reaped": all(
            item["process_group_reaped"] for item in all_receipts
        ),
        "all_cpu_charged": all(
            item["rusage_user_cpu_ns"] + item["rusage_system_cpu_ns"] > 0
            for item in all_receipts
        ),
        "all_rss_sampled": all(
            item["peak_group_rss_kib"] > 0 for item in all_receipts
        ),
        "component_statuses_bound": all(
            item["expected_status_seen"] for item in component_arms.values()
        ),
    }
    counts = {
        decision: sum(row["decision"] == decision for row in rows)
        for decision in (
            "REJECT_NATIVE_DUPLICATE",
            "QUARANTINE_REQUIRED_UNSUPPORTED",
            "QUARANTINE_NONIDENTICAL",
        )
    }
    payload = {
        "version": "FOUNDRY_TENSOR_NATIVE_RESOURCE_AUDIT_V1",
        "status": (
            "TENSOR_NATIVE_RESOURCE_COMPONENT_READY"
            if all(gates.values())
            else "TENSOR_NATIVE_RESOURCE_COMPONENT_FAIL"
        ),
        "library_file_sha256": hashlib.sha256(library_raw).hexdigest(),
        "rows": rows,
        "decision_counts": counts,
        "compiler_resource_receipts": compiler_receipts,
        "component_resource_receipts": component_arms,
        "gates": gates,
        "P3": {
            "new_tensor_forge_arms_integrated": all(gates.values()),
            "external_controls_integrated": False,
            "complete": False,
        },
        "P5": {
            "future_candidate_audit_executed": all(gates.values()),
            "current_candidates_classified": all(gates.values()),
            "admitted": 0,
            "complete": False,
        },
        "limits": [
            "nonidentical generated code is quarantined rather than treated as proof of native novelty",
            "sparse required-unsupported is explicit and supplies no compiler comparison",
            "external controls and the final prospective arm matrix remain outside P3 coverage",
            "process-group metering still requires final containment against new-session escape",
        ],
    }
    (RESULTS / "phase12_tensor_native_resource.json").write_text(
        canonical_json(payload) + "\n", encoding="utf-8"
    )
    print(
        "FOUNDRY_PHASE12_TENSOR_NATIVE_RESOURCE_PASS"
        f" tools={len(rows)}"
        f" duplicate={counts['REJECT_NATIVE_DUPLICATE']}"
        f" unsupported={counts['QUARANTINE_REQUIRED_UNSUPPORTED']}"
        f" nonidentical={counts['QUARANTINE_NONIDENTICAL']}"
        " p3_complete=false p5_complete=false"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--worker", type=int)
    args = parser.parse_args()
    if args.worker is None:
        orchestrate()
    else:
        worker(args.worker)


if __name__ == "__main__":
    main()
