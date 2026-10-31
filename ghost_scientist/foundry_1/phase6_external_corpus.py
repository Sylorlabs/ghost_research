#!/usr/bin/env python3
"""Phase 6: pin and export the installed upstream PyTorch Export DB corpus."""

from __future__ import annotations

import hashlib
import importlib.metadata
import json
import pathlib
from collections import Counter
from typing import Any

from independent_evaluator import canonical_json


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def target_name(target: object) -> str:
    text = str(target)
    return text.replace("<built-in function ", "").replace(">", "")


def run() -> None:
    import torch
    from torch._export.db.case import SupportLevel
    from torch._export.db.examples import all_examples

    distribution = importlib.metadata.distribution("torch")
    package_root = pathlib.Path(torch.__file__).resolve().parent
    dist_root = pathlib.Path(distribution.locate_file(""))
    license_candidates = [
        dist_root / str(item)
        for item in distribution.files or []
        if str(item).endswith("dist-info/LICENSE")
    ]
    record_candidates = [
        dist_root / str(item)
        for item in distribution.files or []
        if str(item).endswith("dist-info/RECORD")
    ]
    if len(license_candidates) != 1 or len(record_candidates) != 1:
        raise RuntimeError("torch wheel provenance files are ambiguous")
    license_path = license_candidates[0]
    record_path = record_candidates[0]
    examples_root = package_root / "_export/db/examples"

    rows: list[dict[str, Any]] = []
    tag_counts: Counter[str] = Counter()
    supported = 0
    exported = 0
    for name, case in sorted(all_examples().items()):
        source = examples_root / f"{name}.py"
        if not source.is_file():
            raise RuntimeError(f"missing upstream example source {name}")
        support = case.support_level == SupportLevel.SUPPORTED
        row: dict[str, Any] = {
            "name": name,
            "source_sha256": sha(source),
            "source_bytes": source.stat().st_size,
            "support_level": str(case.support_level),
            "tags": sorted(case.tags),
            "exported": False,
            "graph_sha256": None,
            "node_count": None,
            "operator_histogram": None,
            "error": None,
        }
        tag_counts.update(case.tags)
        if support:
            supported += 1
            try:
                kwargs = {}
                if getattr(case, "dynamic_shapes", None) is not None:
                    kwargs["dynamic_shapes"] = case.dynamic_shapes
                exported_program = torch.export.export(
                    case.model,
                    case.example_args,
                    case.example_kwargs or {},
                    **kwargs,
                )
                nodes = []
                histogram: Counter[str] = Counter()
                for node in exported_program.graph.nodes:
                    target = target_name(node.target)
                    nodes.append({"op": node.op, "target": target})
                    if node.op == "call_function":
                        histogram[target] += 1
                row.update(
                    {
                        "exported": True,
                        "graph_sha256": hashlib.sha256(
                            canonical_json(nodes).encode()
                        ).hexdigest(),
                        "node_count": len(nodes),
                        "operator_histogram": dict(sorted(histogram.items())),
                    }
                )
                exported += 1
            except Exception as exc:
                row["error"] = f"{type(exc).__name__}:{str(exc)[:200]}"
        rows.append(row)

    payload = {
        "version": "FOUNDRY_EXTERNAL_CORPUS_INTAKE_V1",
        "status": "EXTERNAL_CORPUS_COMPONENT_READY",
        "upstream": {
            "project": "PyTorch",
            "project_url": "https://github.com/pytorch/pytorch",
            "installed_version": torch.__version__,
            "wheel_record_sha256": sha(record_path),
            "license": distribution.metadata.get("License"),
            "license_sha256": sha(license_path),
            "example_root_relative": "torch/_export/db/examples",
        },
        "rows": rows,
        "summary": {
            "examples": len(rows),
            "upstream_supported": supported,
            "exported": exported,
            "export_failures": supported - exported,
            "unique_tags": len(tag_counts),
            "tag_histogram": dict(sorted(tag_counts.items())),
            "unique_graphs": len(
                {row["graph_sha256"] for row in rows if row["graph_sha256"] is not None}
            ),
        },
        "P2": {
            "independently_authored_pinned_corpus_component": exported == supported and exported > 0,
            "heterogeneous_application_workload_families": False,
            "independent_invocation_trace": False,
            "complete": False,
        },
        "limits": [
            "Export DB is upstream compiler conformance material, not an application workload suite",
            "wheel version and RECORD are pinned but no upstream Git commit is embedded in the wheel",
            "no independently observed invocation frequencies are available",
            "the prospective v6 corpus must be selected from a richer predeclared external pool",
        ],
    }
    (RESULTS / "phase6_external_corpus.json").write_text(
        canonical_json(payload) + "\n", encoding="utf-8"
    )
    summary = payload["summary"]
    print(
        "FOUNDRY_PHASE6_EXTERNAL_CORPUS_PASS"
        f" examples={summary['examples']} exported={summary['exported']}"
        f" unique_graphs={summary['unique_graphs']} unique_tags={summary['unique_tags']}"
        " invocation_trace=false"
    )


if __name__ == "__main__":
    run()

