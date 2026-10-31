#!/usr/bin/env python3
"""Post-freeze heldout generation for Operator v5.1."""

from __future__ import annotations

import hashlib
import pathlib
import random
import sys


HERE = pathlib.Path(__file__).resolve().parent
V5 = HERE.parent / "operator_v5"
sys.path.insert(0, str(V5))

from ghost_operator_core_v5 import canonical_json, file_sha256, load_artifact  # noqa: E402
from ghost_operator_corpus_v5 import (  # noqa: E402
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
from ghost_operator_freeze_v5_1 import verify as verify_freeze  # noqa: E402


SEED_HEX = "0x67686f73745f6f70657261746f725f76355f315f68656c646f75745f3032"


def cases():
    pools = [
        (
            "state_space",
            mamba_projection,
            [(1, 44, 60, 6, 16), (2, 124, 76, 10, 22), (4, 36, 92, 12, 24)],
        ),
        (
            "sparse_graph",
            graph_message_passing,
            [(160, 40, 16, 0.03), (132, 16, 44, 0.04), (224, 36, 20, 0.018)],
        ),
        (
            "cnn",
            conv_batch_norm,
            [(2, 16, 32, 38), (1, 34, 46, 50), (2, 48, 58, 54)],
        ),
        (
            "scientific",
            periodic_diffusion,
            [(2, 36, 52), (1, 84, 100), (1, 152, 112)],
        ),
        (
            "normalization",
            explicit_normalization,
            [(1, 160, 96), (2, 112, 96), (2, 192, 128)],
        ),
        (
            "cnn_layout",
            layout_mlp,
            [(2, 16, 16, 18, 64), (1, 40, 26, 28, 160), (2, 52, 32, 34, 208)],
        ),
        (
            "dense_scientific",
            dense_matrix_chain,
            [(640, 80, 420, 10), (11, 420, 52, 420), (144, 128, 320, 28)],
        ),
        (
            "transformer_control",
            attention_projection_control,
            [(2, 40, 64, 56), (1, 104, 92, 52), (2, 132, 112, 80)],
        ),
    ]
    rng = random.Random(int(SEED_HEX[2:], 16))
    reuse_values = [100, 10_000, 100_000]
    result = []
    index = 0
    for family, builder, shapes in pools:
        reuse = list(reuse_values)
        rng.shuffle(reuse)
        for shape, reuse_calls in zip(shapes, reuse):
            result.append(
                (
                    family,
                    builder,
                    (f"heldout_v5_1_{index:03d}", *shape, reuse_calls),
                )
            )
            index += 1
    return result


def generate() -> None:
    freeze = HERE / "results/protocol_freeze_v5_1.txt"
    output = HERE / "results/heldout_corpus"
    verify_freeze(HERE, freeze)
    if output.exists():
        raise RuntimeError("v5.1 heldout corpus already exists")
    artifacts_dir = output / "artifacts"
    artifacts_dir.mkdir(parents=True)
    manifest_lines = [
        "opaque_id\tphase\tartifact_path\tartifact_sha256\tfamily\tprovenance_sha256"
    ]
    audits = []
    receipts = []
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
        receipts.append(
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
            "GHOST_OPERATOR_HELDOUT_GENERATE_V5_1"
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
                "status": "GHOST_OPERATOR_HELDOUT_GENERATION_V5_1_PASS",
                "phase": "POST_FREEZE_PRE_TRIAL",
                "seed_hex": SEED_HEX,
                "freeze_sha256": file_sha256(freeze),
                "artifact_count": len(receipts),
                "cases": receipts,
                "manifest_sha256": file_sha256(manifest),
                "provenance_sha256": file_sha256(audit),
            }
        )
        + "\n",
        encoding="utf-8",
    )
    print(
        "GHOST_OPERATOR_HELDOUT_GENERATION_V5_1 PASS"
        f" artifacts={len(receipts)}"
        f" manifest_sha256={file_sha256(manifest)}"
        f" provenance_sha256={file_sha256(audit)}"
        f" receipt_sha256={file_sha256(receipt)}",
        flush=True,
    )


if __name__ == "__main__":
    generate()

