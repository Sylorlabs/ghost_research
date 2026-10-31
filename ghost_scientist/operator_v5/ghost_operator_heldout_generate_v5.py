#!/usr/bin/env python3
"""Post-freeze evaluator-owned heldout generation for Operator v5."""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import random

from ghost_operator_core_v5 import canonical_json, file_sha256, load_artifact
from ghost_operator_corpus_v5 import (
    attention_projection_control,
    conv_batch_norm,
    dense_matrix_chain,
    explicit_normalization,
    export_graph_receipt,
    graph_message_passing,
    layout_mlp,
    mamba_projection,
    periodic_diffusion,
    source_receipt,
)
from ghost_operator_freeze_v5 import verify as verify_freeze


SEED_HEX = "0x67686f73745f6f70657261746f725f76355f68656c646f75745f3031"


def cases():
    reuse = [100, 10_000, 100_000]
    pools = [
        (
            "state_space",
            mamba_projection,
            [
                (1, 40, 52, 6, 14),
                (2, 112, 68, 8, 20),
                (3, 56, 84, 12, 18),
            ],
        ),
        (
            "sparse_graph",
            graph_message_passing,
            [
                (144, 48, 12, 0.035),
                (120, 12, 40, 0.045),
                (200, 32, 24, 0.02),
            ],
        ),
        (
            "cnn",
            conv_batch_norm,
            [
                (1, 14, 30, 34),
                (2, 30, 42, 38),
                (1, 52, 60, 48),
            ],
        ),
        (
            "scientific",
            periodic_diffusion,
            [(1, 40, 44), (2, 72, 92), (1, 136, 120)],
        ),
        (
            "normalization",
            explicit_normalization,
            [(1, 96, 96), (2, 120, 96), (2, 176, 128)],
        ),
        (
            "cnn_layout",
            layout_mlp,
            [(1, 18, 14, 16, 72), (2, 30, 22, 24, 120), (1, 60, 34, 38, 240)],
        ),
        (
            "dense_scientific",
            dense_matrix_chain,
            [(512, 72, 400, 9), (9, 400, 50, 400), (128, 120, 300, 24)],
        ),
        (
            "transformer_control",
            attention_projection_control,
            [(1, 36, 56, 56), (2, 80, 88, 44), (1, 144, 104, 72)],
        ),
    ]
    rng = random.Random(int(SEED_HEX[2:], 16))
    result = []
    index = 0
    for family, builder, shapes in pools:
        assigned_reuse = list(reuse)
        rng.shuffle(assigned_reuse)
        for shape, reuse_calls in zip(shapes, assigned_reuse):
            opaque_id = f"heldout_{index:03d}"
            result.append((family, builder, (opaque_id, *shape, reuse_calls)))
            index += 1
    return result


def generate(root: pathlib.Path, freeze: pathlib.Path, output: pathlib.Path) -> None:
    verify_freeze(root, freeze)
    if output.exists():
        raise RuntimeError("heldout corpus output already exists")
    artifacts_dir = output / "artifacts"
    artifacts_dir.mkdir(parents=True)
    manifest_lines = [
        "opaque_id\tphase\tartifact_path\tartifact_sha256\tfamily\tprovenance_sha256"
    ]
    audits = []
    case_receipts = []
    source_cache = {}
    for family, builder, args in cases():
        payload = builder(*args)
        opaque_id = payload["opaque_id"]
        path = artifacts_dir / f"{opaque_id}.json"
        path.write_text(canonical_json(payload) + "\n", encoding="utf-8")
        typed, raw = load_artifact(path)
        if typed.opaque_id != opaque_id:
            raise AssertionError("opaque id drift")
        source = source_cache.setdefault(family, source_receipt(family))
        export = export_graph_receipt(payload)
        provenance = {
            "status": "GHOST_OPERATOR_PROVENANCE_V5",
            "opaque_id": opaque_id,
            "phase": "HELDOUT",
            "family": family,
            "artifact_sha256": hashlib.sha256(raw).hexdigest(),
            "source": source,
            "export": export,
        }
        provenance_sha = hashlib.sha256(canonical_json(provenance).encode()).hexdigest()
        audits.append(canonical_json(provenance))
        manifest_lines.append(
            "\t".join(
                (
                    opaque_id,
                    "HELDOUT",
                    str(path),
                    hashlib.sha256(raw).hexdigest(),
                    family,
                    provenance_sha,
                )
            )
        )
        case_receipts.append(
            {
                "opaque_id": opaque_id,
                "family": family,
                "builder": builder.__name__,
                "arguments": list(args[1:]),
                "artifact_sha256": hashlib.sha256(raw).hexdigest(),
                "torch_export_status": export["torch_export_status"],
            }
        )
        print(
            "GHOST_OPERATOR_HELDOUT_GENERATE_V5"
            f" artifact={opaque_id} family={family}"
            f" export={export['torch_export_status']}",
            flush=True,
        )
    manifest = output / "manifest.tsv"
    audit = output / "provenance.private.jsonl"
    receipt = output / "generation_receipt.json"
    manifest.write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")
    audit.write_text("\n".join(audits) + "\n", encoding="utf-8")
    receipt.write_text(
        canonical_json(
            {
                "status": "GHOST_OPERATOR_HELDOUT_GENERATION_V5_PASS",
                "phase": "POST_FREEZE_PRE_TRIAL",
                "seed_hex": SEED_HEX,
                "freeze_sha256": file_sha256(freeze),
                "artifact_count": len(case_receipts),
                "cases": case_receipts,
                "manifest_sha256": file_sha256(manifest),
                "provenance_sha256": file_sha256(audit),
            }
        )
        + "\n",
        encoding="utf-8",
    )
    print(
        "GHOST_OPERATOR_HELDOUT_GENERATION_V5 PASS"
        f" artifacts={len(case_receipts)}"
        f" manifest_sha256={file_sha256(manifest)}"
        f" provenance_sha256={file_sha256(audit)}"
        f" receipt_sha256={file_sha256(receipt)}",
        flush=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root", default=str(pathlib.Path(__file__).resolve().parent)
    )
    parser.add_argument("--freeze")
    parser.add_argument("--output")
    args = parser.parse_args()
    root = pathlib.Path(args.root).resolve()
    freeze = (
        pathlib.Path(args.freeze).resolve()
        if args.freeze
        else root / "results/protocol_freeze_v5.txt"
    )
    output = (
        pathlib.Path(args.output).resolve()
        if args.output
        else root / "results/heldout_corpus"
    )
    generate(root, freeze, output)


if __name__ == "__main__":
    main()

