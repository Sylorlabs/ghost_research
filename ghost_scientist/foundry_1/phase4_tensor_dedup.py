#!/usr/bin/env python3
"""Phase 4: audit v5.1 tools against reference and TorchInductor IR."""

from __future__ import annotations

import hashlib
import json
import pathlib
import re
import sys
import time
from collections import defaultdict
from typing import Any


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
V5 = ROOT / "ghost_scientist/operator_v5"
V51 = ROOT / "ghost_scientist/operator_v5_1"
RESULTS = HERE / "results"
sys.path.insert(0, str(V5))

from ghost_operator_core_v5 import (  # noqa: E402
    TensorProgramModule,
    canonical_json,
    load_artifact,
    load_plan_text,
    materialize_inputs,
    reference_plan,
    sha256_json,
)


def _sha_text(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def _graph_signature(plan: dict[str, Any]) -> str:
    """Canonical pre-lowering program signature with node IDs alpha-renamed."""
    mapping: dict[str, str] = {}
    nodes = []
    for index, node in enumerate(plan["program"]["nodes"]):
        renamed = f"n{index}"
        mapping[node["id"]] = renamed
        attrs = {
            key: ("CONST_REF" if key.endswith("_constant") else value)
            for key, value in sorted(node["attrs"].items())
        }
        nodes.append(
            {
                "id": renamed,
                "op": node["op"],
                "args": [mapping[item] for item in node["args"]],
                "attrs": attrs,
            }
        )
    payload = {
        "parameter_ops": [item["op"] for item in plan["parameter_program"]["nodes"]],
        "runtime_nodes": nodes,
        "outputs": [mapping[item] for item in plan["program"]["outputs"]],
    }
    return sha256_json(payload)


def _normalize_inductor(code: str) -> str:
    code = re.sub(r"/[^\n'\" ]+/(?:torchinductor|tmp)[^\n'\" ]*", "<PATH>", code)
    code = re.sub(r"\b[a-f0-9]{32,64}\b", "<HASH>", code)
    code = re.sub(r"\bc[0-9a-f]{8,}\b", "<CONST>", code)
    code = re.sub(r"(?m)^#.*$", "", code)
    return "\n".join(line.rstrip() for line in code.splitlines() if line.strip())


def _inductor_digest(artifact, plan: dict[str, Any]) -> tuple[str | None, str | None, int]:
    import torch
    from torch._inductor.utils import run_and_get_code

    module, _ = TensorProgramModule.build(artifact, plan)
    inputs = materialize_inputs(artifact)
    started = time.process_time_ns()
    try:
        compiled = torch.compile(module, backend="inductor", fullgraph=True)
        _result, codes = run_and_get_code(compiled, *inputs)
    except Exception as exc:
        return None, f"{type(exc).__name__}:{str(exc)[:160]}", time.process_time_ns() - started
    normalized = "\n".join(_normalize_inductor(item) for item in codes)
    return _sha_text(normalized), None, time.process_time_ns() - started


def run() -> None:
    from freeze_foundry_1 import verify

    verify()
    artifact_dir = V51 / "results/heldout_corpus/artifacts"
    plan_dir = V51 / "results/heldout_trial/candidate_plans"
    artifacts = {path.stem: path for path in artifact_dir.glob("*.json")}
    plans = {path.stem: path for path in plan_dir.glob("*.json")}
    if set(artifacts) != set(plans) or len(artifacts) != 24:
        raise RuntimeError("v5.1 artifact/plan coverage mismatch")

    rows = []
    signature_groups: dict[tuple[str, str], list[int]] = defaultdict(list)
    loaded: list[tuple[Any, dict[str, Any], dict[str, Any]]] = []
    for index, opaque_id in enumerate(sorted(artifacts)):
        artifact, _ = load_artifact(artifacts[opaque_id])
        candidate = dict(load_plan_text(plans[opaque_id].read_text(), artifact))
        stock = reference_plan(artifact)
        candidate_sig = _graph_signature(candidate)
        stock_sig = _graph_signature(stock)
        exact = canonical_json(candidate) == canonical_json(stock)
        row = {
            "opaque_id": opaque_id,
            "artifact_sha256": hashlib.sha256(artifacts[opaque_id].read_bytes()).hexdigest(),
            "candidate_plan_sha256": hashlib.sha256(plans[opaque_id].read_bytes()).hexdigest(),
            "candidate_pre_lowering_ir_sha256": candidate_sig,
            "stock_pre_lowering_ir_sha256": stock_sig,
            "exact_plan_duplicate": exact,
            "pre_lowering_ir_duplicate": candidate_sig == stock_sig,
            "derived_parameter_nodes": len(candidate["parameter_program"]["nodes"]),
        }
        rows.append(row)
        loaded.append((artifact, candidate, stock))
        signature_groups[(candidate_sig, stock_sig)].append(index)

    representatives = [indices[0] for _key, indices in sorted(signature_groups.items())]
    compile_receipts = []
    for index in representatives:
        artifact, candidate, stock = loaded[index]
        candidate_digest, candidate_error, candidate_cpu = _inductor_digest(
            artifact, candidate
        )
        stock_digest, stock_error, stock_cpu = _inductor_digest(artifact, stock)
        equivalent = (
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
        receipt = {
            "opaque_id": rows[index]["opaque_id"],
            "candidate_inductor_sha256": candidate_digest,
            "stock_inductor_sha256": stock_digest,
            "candidate_error": candidate_error,
            "stock_error": stock_error,
            "candidate_cpu_ns": candidate_cpu,
            "stock_cpu_ns": stock_cpu,
            "byte_normalized_inductor_duplicate": equivalent,
            "required_unsupported_sparse": required_unsupported,
        }
        compile_receipts.append(receipt)
        for member in signature_groups[
            (
                rows[index]["candidate_pre_lowering_ir_sha256"],
                rows[index]["stock_pre_lowering_ir_sha256"],
            )
        ]:
            rows[member]["representative_inductor_receipt"] = rows[index]["opaque_id"]
            rows[member]["representative_inductor_duplicate"] = equivalent

    payload = {
        "version": "FOUNDRY_TENSOR_DEDUP_AUDIT_V1",
        "status": "PARTIAL_NATIVE_DEDUP_COMPONENT",
        "v5_1_freeze_sha256": hashlib.sha256(
            (V51 / "results/protocol_freeze_v5_1.txt").read_bytes()
        ).hexdigest(),
        "rows": rows,
        "compile_receipts": compile_receipts,
        "summary": {
            "plans": len(rows),
            "pre_lowering_exact_duplicates": sum(
                int(item["pre_lowering_ir_duplicate"]) for item in rows
            ),
            "representative_signatures": len(representatives),
            "inductor_receipts_completed": sum(
                int(item["candidate_error"] is None and item["stock_error"] is None)
                for item in compile_receipts
            ),
            "inductor_required_unsupported": sum(
                int(item["required_unsupported_sparse"]) for item in compile_receipts
            ),
            "normalized_inductor_duplicates": sum(
                int(item["byte_normalized_inductor_duplicate"])
                for item in compile_receipts
            ),
        },
        "limits": [
            "normalized generated-code equality is a sufficient duplicate witness, not a completeness proof",
            "non-identical generated code does not prove compiler-native novelty",
            "audit covers the frozen v5.1 selected plans, not future Foundry tensor tools",
            "TorchInductor sparse-tensor rejection is retained as required-unsupported rather than compiler evidence",
        ],
    }
    (RESULTS / "phase4_tensor_dedup.json").write_text(
        canonical_json(payload) + "\n", encoding="utf-8"
    )
    summary = payload["summary"]
    print(
        "FOUNDRY_PHASE4_TENSOR_DEDUP_PASS"
        f" plans={summary['plans']}"
        f" signatures={summary['representative_signatures']}"
        f" compiled={summary['inductor_receipts_completed']}"
        f" required_unsupported={summary['inductor_required_unsupported']}"
        f" inductor_duplicates={summary['normalized_inductor_duplicates']}"
    )


if __name__ == "__main__":
    run()
