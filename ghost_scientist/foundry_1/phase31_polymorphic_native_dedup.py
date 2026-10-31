#!/usr/bin/env python3
"""Native/compiler dedup for evidence-constrained polymorphic tools."""

from __future__ import annotations

import hashlib
import json

import torch

from external_validation_v2_2_runtime import constructors as calibration_constructors
from external_validation_v4_runtime import instantiate as validation_instantiate
from phase26_independent_semantic_evaluator import (
    CapturingInterpreter,
    execute_tool,
    max_error,
)
from phase27_semantic_native_dedup import (
    SemanticToolModule,
    StockCompositionModule,
    compile_receipt,
)
from phase30_independent_polymorphic_evaluator import (
    LIBRARY,
    RESULTS,
    matches,
    parse_library,
)


def graph_witnesses(workloads):
    rows = []
    for workload in workloads:
        try:
            exported = torch.export.export(
                workload["model"], workload["args"], workload["kwargs"], strict=True
            )
            module = exported.module()
            interpreter = CapturingInterpreter(module)
            interpreter.run(*workload["args"], **workload["kwargs"])
            rows.append((workload["family"], module, interpreter))
        except Exception:
            continue
    return rows


def calibration_workloads():
    rows = []
    for _family, construct in calibration_constructors():
        try:
            rows.append(construct())
        except Exception:
            continue
    return rows


def run() -> None:
    raw = LIBRARY.read_bytes()
    library = parse_library(raw)
    validation = graph_witnesses(validation_instantiate())
    calibration = graph_witnesses(calibration_workloads())
    rows = []
    for tool in library["tools"]:
        witness = None
        witness_class = None
        for family, module, interpreter in validation:
            found, _, _ = matches(tool, module.graph)
            if found:
                witness = (family, interpreter, found[0])
                witness_class = "prospective_validation"
                break
        if witness is None:
            for family, module, interpreter in calibration:
                found, _, _ = matches(tool, module.graph)
                if found:
                    witness = (family, interpreter, found[0])
                    witness_class = "calibration_fallback"
                    break
        if witness is None:
            raise RuntimeError(f"no native witness for {tool['tool_id']}")
        family, interpreter, (path, bindings) = witness
        inputs = tuple(
            interpreter.values[bindings[index]]
            for index in range(len(tool["inputs"]))
        )
        semantic_module = SemanticToolModule(tool)
        stock_module = StockCompositionModule(tool)
        with torch.no_grad():
            semantic_output = semantic_module(*inputs)
            stock_output = stock_module(*inputs)
        error = max_error(semantic_output, stock_output)
        if not error <= 1.0e-6:
            raise RuntimeError(f"polymorphic stock mismatch {tool['tool_id']}")
        semantic_receipt = compile_receipt(semantic_module, inputs)
        stock_receipt = compile_receipt(stock_module, inputs)
        compiled_both = (
            semantic_receipt["error"] is None and stock_receipt["error"] is None
        )
        duplicate = (
            compiled_both
            and semantic_receipt["code_sha256"]
            == stock_receipt["code_sha256"]
        )
        required_unsupported = (
            not compiled_both
            and semantic_receipt["error"] is not None
            and stock_receipt["error"] is not None
        )
        rows.append(
            {
                "tool_id": tool["tool_id"],
                "source_tool_id": tool["source_tool_id"],
                "witness_class": witness_class,
                "witness_family": family,
                "witness_nodes": [node.name for node in path],
                "stock_decomposition_exact": True,
                "decomposition_max_abs_error": error,
                "runtime_rewrite_exists": False,
                "semantic_compile": {
                    key: value
                    for key, value in semantic_receipt.items()
                    if key != "output"
                },
                "stock_compile": {
                    key: value
                    for key, value in stock_receipt.items()
                    if key != "output"
                },
                "normalized_inductor_duplicate": duplicate,
                "required_unsupported": required_unsupported,
                "decision": "REJECT_NATIVE_COMPOSITE_DUPLICATE",
            }
        )
    payload = {
        "version": "FOUNDRY_POLYMORPHIC_NATIVE_DEDUP_V1",
        "status": "POLYMORPHIC_NATIVE_DEDUP_COMPLETE",
        "library_sha256": hashlib.sha256(raw).hexdigest(),
        "rows": rows,
        "summary": {
            "tools": len(rows),
            "validation_witnesses": sum(
                row["witness_class"] == "prospective_validation" for row in rows
            ),
            "calibration_fallbacks": sum(
                row["witness_class"] == "calibration_fallback" for row in rows
            ),
            "stock_decomposition_duplicates": len(rows),
            "compiled_both": sum(
                row["semantic_compile"]["error"] is None
                and row["stock_compile"]["error"] is None
                for row in rows
            ),
            "normalized_inductor_duplicates": sum(
                row["normalized_inductor_duplicate"] for row in rows
            ),
            "required_unsupported": sum(row["required_unsupported"] for row in rows),
            "rejected": len(rows),
            "admitted": 0,
        },
        "P5": {
            "current_candidate_audit_executed": True,
            "all_candidates_classified": True,
            "runtime_inventions_admitted": 0,
            "complete": False,
        },
        "limits": [
            "polymorphic typing changes admissibility but not the stock ATen decomposition",
            "exact stock decomposition rejects runtime novelty",
            "compiler equality is a sufficient additional duplicate witness",
            "compiler inequality is not novelty evidence",
        ],
    }
    (RESULTS / "phase31_polymorphic_native_dedup.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE31_POLYMORPHIC_NATIVE_PASS"
        f" tools={len(rows)}"
        f" validation_witnesses={payload['summary']['validation_witnesses']}"
        f" compiled={payload['summary']['compiled_both']}"
        f" inductor_duplicates={payload['summary']['normalized_inductor_duplicates']}"
        f" unsupported={payload['summary']['required_unsupported']}"
        " admitted=0"
    )


if __name__ == "__main__":
    run()
