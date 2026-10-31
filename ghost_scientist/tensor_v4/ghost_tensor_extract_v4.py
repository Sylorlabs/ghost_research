#!/usr/bin/env python3
"""Extract typed parallel-projection artifacts from installed Transformer code.

The public candidate artifact contains only opaque tensor/type metadata.  The
private audit binds it to an actual torch.export FX graph, installed source
file, model class, configuration, and source hash.
"""

from __future__ import annotations

import argparse
import hashlib
import inspect
import json
import pathlib
import random
from collections.abc import Sequence
from typing import Any

from ghost_tensor_core_v4 import ARTIFACT_VERSION, canonical_json


SUPPORTED_FAMILIES = ("bert", "roberta", "t5", "bart", "llama")


def file_sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def opaque_id(seed: int, index: int) -> str:
    material = f"GHOST_TENSOR_V4:{seed:032x}:{index}".encode("ascii")
    return "tensor_" + hashlib.sha256(material).hexdigest()[:16]


def build_export(
    family: str,
    *,
    batch: int,
    sequence: int,
    hidden: int,
    heads: int,
    key_value_heads: int,
):
    import torch

    if family == "bert":
        from transformers import BertConfig, BertModel

        config = BertConfig(
            hidden_size=hidden,
            num_hidden_layers=1,
            num_attention_heads=heads,
            intermediate_size=hidden * 2,
            vocab_size=128,
            max_position_embeddings=max(32, sequence + 2),
        )
        model = BertModel(config).eval()
        module = model.encoder.layer[0].attention.self
        sample = torch.randn(batch, sequence, hidden)
        exported = torch.export.export(
            module,
            (sample,),
            {"attention_mask": torch.zeros(batch, 1, 1, sequence)},
        )
        projections = (module.query, module.key, module.value)
        projection_heads = (heads, heads, heads)
    elif family == "roberta":
        from transformers import RobertaConfig, RobertaModel

        config = RobertaConfig(
            hidden_size=hidden,
            num_hidden_layers=1,
            num_attention_heads=heads,
            intermediate_size=hidden * 2,
            vocab_size=128,
            max_position_embeddings=max(34, sequence + 4),
        )
        model = RobertaModel(config).eval()
        module = model.encoder.layer[0].attention.self
        sample = torch.randn(batch, sequence, hidden)
        exported = torch.export.export(
            module,
            (sample,),
            {"attention_mask": torch.zeros(batch, 1, 1, sequence)},
        )
        projections = (module.query, module.key, module.value)
        projection_heads = (heads, heads, heads)
    elif family == "t5":
        from transformers import T5Config, T5Model

        head_dim = hidden // heads
        config = T5Config(
            d_model=hidden,
            d_ff=hidden * 2,
            num_layers=1,
            num_heads=heads,
            d_kv=head_dim,
            vocab_size=128,
        )
        model = T5Model(config).eval()
        module = model.encoder.block[0].layer[0].SelfAttention
        sample = torch.randn(batch, sequence, hidden)
        exported = torch.export.export(
            module,
            (sample,),
            {"mask": torch.zeros(batch, 1, sequence, sequence)},
        )
        projections = (module.q, module.k, module.v)
        projection_heads = (heads, heads, heads)
    elif family == "bart":
        from transformers import BartConfig, BartModel

        config = BartConfig(
            d_model=hidden,
            encoder_layers=1,
            decoder_layers=1,
            encoder_attention_heads=heads,
            decoder_attention_heads=heads,
            encoder_ffn_dim=hidden * 2,
            decoder_ffn_dim=hidden * 2,
            vocab_size=128,
            max_position_embeddings=max(32, sequence + 2),
        )
        model = BartModel(config).eval()
        module = model.encoder.layers[0].self_attn
        sample = torch.randn(batch, sequence, hidden)
        exported = torch.export.export(module, (sample,), {})
        projections = (module.q_proj, module.k_proj, module.v_proj)
        projection_heads = (heads, heads, heads)
    elif family == "llama":
        from transformers import LlamaConfig, LlamaModel

        config = LlamaConfig(
            hidden_size=hidden,
            intermediate_size=hidden * 2,
            num_hidden_layers=1,
            num_attention_heads=heads,
            num_key_value_heads=key_value_heads,
            vocab_size=128,
            max_position_embeddings=max(32, sequence + 2),
        )
        model = LlamaModel(config).eval()
        module = model.layers[0].self_attn
        sample = torch.randn(batch, sequence, hidden)
        positions = torch.arange(sequence).unsqueeze(0).expand(batch, -1)
        position_embeddings = model.rotary_emb(sample, positions)
        exported = torch.export.export(module, (sample, position_embeddings), {})
        projections = (module.q_proj, module.k_proj, module.v_proj)
        projection_heads = (heads, key_value_heads, key_value_heads)
    else:
        raise ValueError(f"unsupported family: {family}")

    graph = exported.graph_module.graph
    linear_nodes = [
        node
        for node in graph.nodes
        if node.op == "call_function" and "aten.linear.default" in str(node.target)
    ]
    same_input: dict[str, list[Any]] = {}
    for node in linear_nodes:
        input_node = node.args[0]
        same_input.setdefault(str(input_node), []).append(node)
    clusters = [nodes for nodes in same_input.values() if len(nodes) >= 3]
    if not clusters:
        raise RuntimeError(f"{family}: export contains no three-linear same-input cluster")
    first_cluster = clusters[0]
    if len(first_cluster) != 3:
        raise RuntimeError(f"{family}: first parallel projection cluster is not exactly three")
    for projection in projections:
        if projection.in_features != hidden:
            raise RuntimeError(f"{family}: projection input width mismatch")
    source_path_text = inspect.getsourcefile(type(module))
    if source_path_text is None:
        raise RuntimeError(f"{family}: module source path unavailable")
    source_path = pathlib.Path(source_path_text).resolve()
    config_dict = {
        key: value
        for key, value in config.to_dict().items()
        if isinstance(value, (str, int, float, bool, type(None)))
    }
    return {
        "graph_text": str(graph),
        "graph_sha256": hashlib.sha256(str(graph).encode("utf-8")).hexdigest(),
        "source_path": str(source_path),
        "source_sha256": file_sha256(source_path),
        "module_class": f"{type(module).__module__}.{type(module).__qualname__}",
        "config": config_dict,
        "projections": projections,
        "projection_heads": projection_heads,
        "linear_node_count": len(linear_nodes),
        "parallel_cluster_count": len(clusters),
    }


def generate(
    output_dir: pathlib.Path,
    private_audit: pathlib.Path,
    manifest: pathlib.Path,
    *,
    phase: str,
    families: Sequence[str],
    count: int,
    seed: int,
) -> None:
    if phase not in ("DEVELOPMENT", "VALIDATION", "HELDOUT"):
        raise ValueError("invalid phase")
    if not families or any(family not in SUPPORTED_FAMILIES for family in families):
        raise ValueError("invalid extraction family")
    output_dir.mkdir(parents=True, exist_ok=True)
    private_audit.parent.mkdir(parents=True, exist_ok=True)
    manifest.parent.mkdir(parents=True, exist_ok=True)
    rng = random.Random(seed)
    shape_options = (
        (1, 1, 2, 8),
        (1, 4, 2, 8),
        (1, 8, 4, 8),
        (1, 16, 4, 8),
        (1, 32, 4, 16),
        (2, 32, 4, 16),
        (2, 64, 4, 32),
        (4, 64, 8, 32),
    )
    audit_rows: list[str] = []
    manifest_rows = [
        "opaque_id\tphase\tartifact_path\tartifact_sha256\tinput_shape\tprojection_outs"
    ]
    for index in range(count):
        family = families[index % len(families)]
        batch, sequence, heads, head_dim = shape_options[index % len(shape_options)]
        if index >= len(shape_options):
            batch, sequence, heads, head_dim = rng.choice(shape_options)
        hidden = heads * head_dim
        key_value_heads = heads if family != "llama" else max(1, heads // 2)
        torch_seed = rng.getrandbits(63)
        import torch

        torch.manual_seed(torch_seed)
        extracted = build_export(
            family,
            batch=batch,
            sequence=sequence,
            hidden=hidden,
            heads=heads,
            key_value_heads=key_value_heads,
        )
        identifier = opaque_id(seed, index)
        weight_seed = rng.getrandbits(64)
        projection_payload = []
        projection_outs: list[str] = []
        for projection_index, (projection, projection_heads) in enumerate(
            zip(
                extracted["projections"],
                extracted["projection_heads"],
                strict=True,
            )
        ):
            projection_payload.append(
                {
                    "opaque_parameter": f"p{projection_index}",
                    "out_features": projection.out_features,
                    "heads": projection_heads,
                    "bias": projection.bias is not None,
                }
            )
            projection_outs.append(str(projection.out_features))
        public = {
            "version": ARTIFACT_VERSION,
            "opaque_id": identifier,
            "input": {
                "shape": [batch, sequence, hidden],
                "dtype": "float32",
                "layout": "contiguous",
            },
            "projections": projection_payload,
            "weight_seed_hex": f"0x{weight_seed:016x}",
            "output_contract": "BHTD_last_dim_stride_1",
        }
        public_text = canonical_json(public) + "\n"
        artifact_path = output_dir / f"{identifier}.json"
        artifact_path.write_text(public_text, encoding="utf-8")
        public_sha = hashlib.sha256(public_text.encode("utf-8")).hexdigest()
        audit = {
            "opaque_id": identifier,
            "phase": phase,
            "public_sha256": public_sha,
            "family": family,
            "source_path": extracted["source_path"],
            "source_sha256": extracted["source_sha256"],
            "module_class": extracted["module_class"],
            "config": extracted["config"],
            "torch_seed": torch_seed,
            "fx_graph_sha256": extracted["graph_sha256"],
            "fx_graph": extracted["graph_text"],
            "linear_node_count": extracted["linear_node_count"],
            "parallel_cluster_count": extracted["parallel_cluster_count"],
        }
        audit_rows.append(canonical_json(audit))
        manifest_rows.append(
            f"{identifier}\t{phase}\t{artifact_path.as_posix()}\t{public_sha}"
            f"\t{batch}x{sequence}x{hidden}\t{','.join(projection_outs)}"
        )
    private_audit.write_text("\n".join(audit_rows) + "\n", encoding="utf-8")
    manifest.write_text("\n".join(manifest_rows) + "\n", encoding="utf-8")
    print(
        "GHOST_TENSOR_EXTRACT_V4 PASS"
        f" phase={phase} count={count} families={','.join(families)}"
        f" seed_hex=0x{seed:032x}"
        f" manifest_sha256={file_sha256(manifest)}"
        f" private_audit_sha256={file_sha256(private_audit)}"
    )


def selftest() -> None:
    import tempfile

    with tempfile.TemporaryDirectory(prefix="ghost-tensor-extract-") as directory_text:
        directory = pathlib.Path(directory_text)
        generate(
            directory / "public",
            directory / "private.jsonl",
            directory / "manifest.tsv",
            phase="VALIDATION",
            families=("bert",),
            count=1,
            seed=0x1234,
        )
        public_files = list((directory / "public").glob("*.json"))
        if len(public_files) != 1:
            raise AssertionError("extractor did not emit one public artifact")
        public = json.loads(public_files[0].read_text(encoding="utf-8"))
        forbidden = {"family", "source_path", "source_sha256", "module_class", "fx_graph"}
        if forbidden & set(public):
            raise AssertionError("private provenance leaked into candidate artifact")
        private = json.loads((directory / "private.jsonl").read_text(encoding="utf-8"))
        if private["family"] != "bert" or not private["fx_graph_sha256"]:
            raise AssertionError("private provenance is incomplete")
    print(
        "GHOST_TENSOR_EXTRACT_V4_SELFTEST PASS"
        " torch_export=true same_input_cluster=true provenance_private=true"
    )


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    generate_parser = subparsers.add_parser("generate")
    generate_parser.add_argument("output_dir")
    generate_parser.add_argument("private_audit")
    generate_parser.add_argument("manifest")
    generate_parser.add_argument("--phase", required=True)
    generate_parser.add_argument("--families", required=True)
    generate_parser.add_argument("--count", type=int, required=True)
    generate_parser.add_argument("--seed-hex", required=True)
    subparsers.add_parser("selftest")
    args = parser.parse_args(argv)
    if args.command == "selftest":
        selftest()
        return
    generate(
        pathlib.Path(args.output_dir),
        pathlib.Path(args.private_audit),
        pathlib.Path(args.manifest),
        phase=args.phase,
        families=tuple(args.families.split(",")),
        count=args.count,
        seed=int(args.seed_hex.removeprefix("0x"), 16),
    )


if __name__ == "__main__":
    main()
