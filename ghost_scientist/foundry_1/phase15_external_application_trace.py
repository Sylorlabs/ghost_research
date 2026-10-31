#!/usr/bin/env python3
"""Phase 15: execute frozen upstream application models and record real traces."""

from __future__ import annotations

import collections
import hashlib
import importlib.util
import json
import pathlib
from typing import Any

import torch
from torch.utils._python_dispatch import TorchDispatchMode

from freeze_external_application_intake import MANIFEST, verify


HERE = pathlib.Path(__file__).resolve().parent
WORKLOADS = HERE / "external_workloads"
RESULTS = HERE / "results"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def load_module(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def tensor_signature(value: object) -> object:
    if isinstance(value, torch.Tensor):
        return {
            "shape": list(value.shape),
            "dtype": str(value.dtype),
            "layout": str(value.layout),
            "requires_grad": bool(value.requires_grad),
        }
    if isinstance(value, (list, tuple)):
        return [tensor_signature(item) for item in value]
    if isinstance(value, dict):
        return {
            str(key): tensor_signature(item)
            for key, item in sorted(value.items(), key=lambda pair: str(pair[0]))
        }
    if value is None or type(value) in (bool, int, float, str):
        return value
    return {"python_type": type(value).__name__}


class InvocationRecorder(TorchDispatchMode):
    def __init__(self) -> None:
        super().__init__()
        self.rows: list[dict[str, object]] = []

    def __torch_dispatch__(self, func, types, args=(), kwargs=None):
        kwargs = kwargs or {}
        output = func(*args, **kwargs)
        self.rows.append(
            {
                "ordinal": len(self.rows),
                "operator": str(func),
                "args": tensor_signature(args),
                "kwargs": tensor_signature(kwargs),
                "outputs": tensor_signature(output),
            }
        )
        return output


def instantiate() -> list[dict[str, Any]]:
    torch.manual_seed(0xF015)
    mnist = load_module("foundry_ext_mnist", WORKLOADS / "mnist_model.py")
    vae = load_module("foundry_ext_vae", WORKLOADS / "vae_model.py")
    sequence = load_module("foundry_ext_sequence", WORKLOADS / "sequence_model.py")
    super_resolution = load_module(
        "foundry_ext_super_resolution", WORKLOADS / "super_resolution_model.py"
    )
    return [
        {
            "family": "image_classification",
            "snapshot": "mnist_model.py",
            "model": mnist.Net().eval(),
            "args": (torch.randn(2, 1, 28, 28),),
            "kwargs": {},
        },
        {
            "family": "variational_autoencoding",
            "snapshot": "vae_model.py",
            "model": vae.VAE().eval(),
            "args": (torch.randn(2, 1, 28, 28),),
            "kwargs": {},
        },
        {
            "family": "time_series_recurrence",
            "snapshot": "sequence_model.py",
            "model": sequence.Sequence().double().eval(),
            "args": (torch.randn(2, 12, dtype=torch.double),),
            "kwargs": {},
        },
        {
            "family": "image_super_resolution",
            "snapshot": "super_resolution_model.py",
            "model": super_resolution.Net(2).eval(),
            "args": (torch.randn(1, 1, 12, 12),),
            "kwargs": {},
        },
    ]


def run() -> None:
    freeze = verify()
    intake = json.loads((WORKLOADS / "SOURCE_INTAKE.json").read_text())
    expected_families = [item["family"] for item in intake["workloads"]]
    rows = []
    for workload in instantiate():
        recorder = InvocationRecorder()
        torch.manual_seed(0xF015)
        with torch.no_grad(), recorder:
            output = workload["model"](*workload["args"], **workload["kwargs"])
        trace_raw = canonical(recorder.rows).encode()
        export_error = None
        graph_text = None
        try:
            torch.manual_seed(0xF015)
            exported = torch.export.export(
                workload["model"],
                workload["args"],
                workload["kwargs"],
                strict=True,
            )
            graph_text = str(exported.graph_module.graph)
        except Exception as exc:
            export_error = f"{type(exc).__name__}:{str(exc)[:400]}"
        histogram = collections.Counter(item["operator"] for item in recorder.rows)
        snapshot_path = WORKLOADS / workload["snapshot"]
        rows.append(
            {
                "family": workload["family"],
                "snapshot": workload["snapshot"],
                "snapshot_sha256": sha_bytes(snapshot_path.read_bytes()),
                "input_signature": tensor_signature(workload["args"]),
                "output_signature": tensor_signature(output),
                "invocations": len(recorder.rows),
                "unique_operators": len(histogram),
                "operator_histogram": dict(sorted(histogram.items())),
                "trace_sha256": sha_bytes(trace_raw),
                "trace": recorder.rows,
                "export_status": "PASS" if export_error is None else "REQUIRED_FAIL",
                "export_error": export_error,
                "export_graph_sha256": (
                    sha_bytes(graph_text.encode()) if graph_text is not None else None
                ),
                "export_graph": graph_text,
            }
        )
    gates = {
        "four_upstream_application_families": (
            [row["family"] for row in rows] == expected_families
            and len(set(expected_families)) == 4
        ),
        "all_runtime_traces_nonempty": all(row["invocations"] > 0 for row in rows),
        "all_runtime_traces_operator_diverse": all(
            row["unique_operators"] >= 3 for row in rows
        ),
        "all_export_graphs_complete": all(row["export_status"] == "PASS" for row in rows),
        "source_intake_preexecution_frozen": (
            freeze["execution_observed"] is False
            and freeze["outcomes_observed"] is False
        ),
        "no_transformer_or_attention_workload": intake["boundary"][
            "transformer_or_attention_workload"
        ]
        is False,
    }
    payload = {
        "version": "FOUNDRY_EXTERNAL_APPLICATION_TRACE_V1",
        "status": (
            "EXTERNAL_APPLICATION_TRACE_COMPONENT_READY"
            if all(gates.values())
            else "EXTERNAL_APPLICATION_TRACE_COMPONENT_PARTIAL"
        ),
        "source_repository": intake["repository"],
        "source_commit": intake["commit"],
        "source_intake_freeze_sha256": sha_bytes(MANIFEST.read_bytes()),
        "gates": gates,
        "rows": rows,
        "summary": {
            "families": len(rows),
            "traced": sum(row["invocations"] > 0 for row in rows),
            "exported": sum(row["export_status"] == "PASS" for row in rows),
            "total_invocations": sum(row["invocations"] for row in rows),
            "unique_trace_digests": len({row["trace_sha256"] for row in rows}),
        },
        "P2": {
            "external_application_sources": gates[
                "four_upstream_application_families"
            ],
            "runtime_invocation_trace": gates["all_runtime_traces_nonempty"],
            "compiler_graphs": gates["all_export_graphs_complete"],
            "forged_tool_domain_adapter": False,
            "deployment_demand_trace": False,
            "complete": False,
        },
        "limits": [
            "model definitions are upstream-authored while input shapes are harness-selected",
            "runtime operator traces are real executions but are not deployment demand logs",
            "model-only excerpts were used for three applications to avoid dataset and CLI side effects",
            "exported ATen graphs are not yet mapped into the frozen forged-tool IR",
        ],
    }
    (RESULTS / "phase15_external_application_trace.json").write_text(
        canonical(payload) + "\n", encoding="utf-8"
    )
    summary = payload["summary"]
    print(
        "FOUNDRY_PHASE15_EXTERNAL_APPLICATION_TRACE"
        f" status={payload['status']}"
        f" families={summary['families']}"
        f" traced={summary['traced']}"
        f" exported={summary['exported']}"
        f" invocations={summary['total_invocations']}"
        " p2_complete=false"
    )


if __name__ == "__main__":
    run()
