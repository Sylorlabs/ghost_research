#!/usr/bin/env python3
"""Development-corpus construction for Ghost Scientist Operator v5.

Family and provenance labels are written only to the private audit/manifest.
Candidate-visible artifacts contain opaque ids, typed values, constants, a
reference tensor program, and output contracts.
"""

from __future__ import annotations

import argparse
import hashlib
import inspect
import json
import pathlib
from collections.abc import Sequence
from typing import Any

from ghost_operator_core_v5 import (
    ARTIFACT_VERSION,
    canonical_json,
    file_sha256,
    load_artifact,
)


def tensor_type(shape: Sequence[int], *, storage: str = "strided") -> dict[str, object]:
    return {"shape": list(shape), "dtype": "float32", "storage": storage}


def input_spec(name: str, shape: Sequence[int], seed: int) -> dict[str, object]:
    return {"name": name, "type": tensor_type(shape), "seed_hex": hex(seed)}


def parameter_spec(
    name: str,
    shape: Sequence[int],
    seed: int,
    *,
    init: dict[str, object] | None = None,
    storage: str = "strided",
) -> dict[str, object]:
    return {
        "name": name,
        "type": tensor_type(shape, storage=storage),
        "seed_hex": hex(seed),
        "init": init or {"kind": "normal", "scale": 0.2},
    }


def node(
    node_id: str, op: str, args: Sequence[str] = (), **attrs: object
) -> dict[str, object]:
    return {"id": node_id, "op": op, "args": list(args), "attrs": attrs}


def output(value: str, shape: Sequence[int], layout: str = "last_dim_stride_1"):
    return {"value": value, "type": tensor_type(shape), "layout": layout}


def artifact(
    opaque_id: str,
    inputs: list[dict[str, object]],
    parameters: list[dict[str, object]],
    constants: dict[str, object],
    nodes: list[dict[str, object]],
    outputs: list[dict[str, object]],
    reuse_calls: int,
) -> dict[str, object]:
    input_names = {item["name"]: f"i{index}" for index, item in enumerate(inputs)}
    parameter_names = {
        item["name"]: f"p{index}" for index, item in enumerate(parameters)
    }
    constant_names = {name: f"c{index}" for index, name in enumerate(constants)}
    node_names = {item["id"]: f"n{index}" for index, item in enumerate(nodes)}

    canonical_inputs = []
    for item in inputs:
        copied = dict(item)
        copied["name"] = input_names[item["name"]]
        canonical_inputs.append(copied)
    canonical_parameters = []
    for item in parameters:
        copied = dict(item)
        copied["name"] = parameter_names[item["name"]]
        canonical_parameters.append(copied)
    canonical_nodes = []
    for item in nodes:
        attrs = dict(item["attrs"])
        if item["op"] == "input":
            attrs["name"] = input_names[attrs["name"]]
        elif item["op"] == "parameter":
            attrs["name"] = parameter_names[attrs["name"]]
        for key, value in tuple(attrs.items()):
            if key.endswith("_constant") and isinstance(value, str):
                attrs[key] = constant_names[value]
        canonical_nodes.append(
            {
                "id": node_names[item["id"]],
                "op": item["op"],
                "args": [node_names[arg] for arg in item["args"]],
                "attrs": attrs,
            }
        )
    canonical_outputs = []
    for item in outputs:
        copied = dict(item)
        copied["value"] = node_names[item["value"]]
        canonical_outputs.append(copied)
    return {
        "version": ARTIFACT_VERSION,
        "opaque_id": opaque_id,
        "inputs": canonical_inputs,
        "parameters": canonical_parameters,
        "constants": {constant_names[name]: value for name, value in constants.items()},
        "reference_program": {
            "nodes": canonical_nodes,
            "outputs": [item["value"] for item in canonical_outputs],
        },
        "outputs": canonical_outputs,
        "reuse_calls": reuse_calls,
    }


def mamba_projection(
    opaque_id: str, batch: int, tokens: int, width: int, dt_rank: int, state: int, reuse: int
) -> dict[str, object]:
    packed = dt_rank + 2 * state
    final = width + 2 * state
    nodes = [
        node("x", "input", name="x"),
        node("xw", "parameter", name="x_weight"),
        node("xb", "parameter", name="x_bias"),
        node("dtw", "parameter", name="dt_weight"),
        node("dtb", "parameter", name="dt_bias"),
        node("projected", "linear", ["x", "xw", "xb"]),
        node("dt", "split_get", ["projected"], dim=-1, sizes_constant="split_sizes", index=0),
        node("state_b", "split_get", ["projected"], dim=-1, sizes_constant="split_sizes", index=1),
        node("state_c", "split_get", ["projected"], dim=-1, sizes_constant="split_sizes", index=2),
        node("delta", "linear", ["dt", "dtw", "dtb"]),
        node("out", "cat", ["delta", "state_b", "state_c"], dim=-1),
    ]
    return artifact(
        opaque_id,
        [input_spec("x", (batch, tokens, width), 0x1001 + width + tokens)],
        [
            parameter_spec("x_weight", (packed, width), 0x2001 + packed),
            parameter_spec("x_bias", (packed,), 0x2002 + packed),
            parameter_spec("dt_weight", (width, dt_rank), 0x2003 + width),
            parameter_spec("dt_bias", (width,), 0x2004 + width),
        ],
        {"split_sizes": [dt_rank, state, state]},
        nodes,
        [output("out", (batch, tokens, final))],
        reuse,
    )


def graph_message_passing(
    opaque_id: str,
    nodes_count: int,
    in_features: int,
    out_features: int,
    density: float,
    reuse: int,
) -> dict[str, object]:
    nodes = [
        node("x", "input", name="x"),
        node("adj", "parameter", name="adjacency"),
        node("w", "parameter", name="weight"),
        node("ws", "parameter", name="skip_weight"),
        node("neighbors", "sparse_mm", ["adj", "x"]),
        node("messages", "matmul", ["neighbors", "w"]),
        node("skip", "matmul", ["x", "ws"]),
        node("out", "add", ["messages", "skip"]),
    ]
    return artifact(
        opaque_id,
        [input_spec("x", (nodes_count, in_features), 0x3100 + nodes_count)],
        [
            parameter_spec(
                "adjacency",
                (nodes_count, nodes_count),
                0x3200 + nodes_count,
                storage="sparse_csr",
                init={"kind": "sparse_csr", "density": density},
            ),
            parameter_spec("weight", (in_features, out_features), 0x3300 + in_features),
            parameter_spec("skip_weight", (in_features, out_features), 0x3400 + out_features),
        ],
        {"split_outputs": [out_features, out_features]},
        nodes,
        [output("out", (nodes_count, out_features))],
        reuse,
    )


def conv_batch_norm(
    opaque_id: str, batch: int, channels: int, height: int, width: int, reuse: int
) -> dict[str, object]:
    nodes = [
        node("x", "input", name="x"),
        node("weight", "parameter", name="conv_weight"),
        node("bias", "parameter", name="conv_bias"),
        node("gamma", "parameter", name="gamma"),
        node("beta", "parameter", name="beta"),
        node("mean", "parameter", name="running_mean"),
        node("variance", "parameter", name="running_variance"),
        node(
            "convolved",
            "conv2d",
            ["x", "weight", "bias"],
            stride=[1, 1],
            padding=[1, 1],
            dilation=[1, 1],
            groups=1,
        ),
        node(
            "out",
            "batch_norm_eval",
            ["convolved", "gamma", "beta", "mean", "variance"],
            epsilon_constant="epsilon",
        ),
    ]
    return artifact(
        opaque_id,
        [input_spec("x", (batch, channels, height, width), 0x4100 + height)],
        [
            parameter_spec("conv_weight", (channels, channels, 3, 3), 0x4200 + channels),
            parameter_spec("conv_bias", (channels,), 0x4300 + channels),
            parameter_spec("gamma", (channels,), 0x4400 + channels, init={"kind": "normal", "scale": 0.1}),
            parameter_spec("beta", (channels,), 0x4500 + channels),
            parameter_spec("running_mean", (channels,), 0x4600 + channels),
            parameter_spec(
                "running_variance",
                (channels,),
                0x4700 + channels,
                init={"kind": "positive", "scale": 0.3, "offset": 0.5},
            ),
        ],
        {"epsilon": 1.0e-5, "channel_scale_shape": [channels, 1, 1, 1]},
        nodes,
        [output("out", (batch, channels, height, width))],
        reuse,
    )


def periodic_diffusion(
    opaque_id: str, batch: int, height: int, width: int, reuse: int
) -> dict[str, object]:
    nodes = [
        node("x", "input", name="x"),
        node("center_scale", "parameter", name="center_scale"),
        node("neighbor_scale", "parameter", name="neighbor_scale"),
        node("north", "roll", ["x"], shifts=[1], dims=[2]),
        node("south", "roll", ["x"], shifts=[-1], dims=[2]),
        node("west", "roll", ["x"], shifts=[1], dims=[3]),
        node("east", "roll", ["x"], shifts=[-1], dims=[3]),
        node("vertical", "add", ["north", "south"]),
        node("horizontal", "add", ["west", "east"]),
        node("neighbors", "add", ["vertical", "horizontal"]),
        node("scaled_neighbors", "mul", ["neighbors", "neighbor_scale"]),
        node("scaled_center", "mul", ["x", "center_scale"]),
        node("out", "add", ["scaled_center", "scaled_neighbors"]),
    ]
    center = 0.96
    neighbor = 0.01
    return artifact(
        opaque_id,
        [input_spec("x", (batch, 1, height, width), 0x5100 + height)],
        [
            parameter_spec("center_scale", (1,), 0x5201, init={"kind": "literal", "value": center}),
            parameter_spec("neighbor_scale", (1,), 0x5202, init={"kind": "literal", "value": neighbor}),
        ],
        {"stencil_center": center, "stencil_neighbor": neighbor},
        nodes,
        [output("out", (batch, 1, height, width))],
        reuse,
    )


def explicit_normalization(
    opaque_id: str, batch: int, rows: int, width: int, reuse: int
) -> dict[str, object]:
    nodes = [
        node("x", "input", name="x"),
        node("gamma", "parameter", name="gamma"),
        node("beta", "parameter", name="beta"),
        node("epsilon", "parameter", name="epsilon"),
        node("mean", "reduce_mean", ["x"], dims=[-1], keepdim=True),
        node("centered", "sub", ["x", "mean"]),
        node("squared", "mul", ["centered", "centered"]),
        node("variance", "reduce_mean", ["squared"], dims=[-1], keepdim=True),
        node("stabilized", "add", ["variance", "epsilon"]),
        node("inverse_std", "rsqrt", ["stabilized"]),
        node("normalized", "mul", ["centered", "inverse_std"]),
        node("scaled", "mul", ["normalized", "gamma"]),
        node("out", "add", ["scaled", "beta"]),
    ]
    return artifact(
        opaque_id,
        [input_spec("x", (batch, rows, width), 0x6100 + width)],
        [
            parameter_spec("gamma", (width,), 0x6200 + width, init={"kind": "ones"}),
            parameter_spec("beta", (width,), 0x6300 + width, init={"kind": "zeros"}),
            parameter_spec("epsilon", (1,), 0x6400 + width, init={"kind": "literal", "value": 1.0e-5}),
        ],
        {"normalized_shape": [width], "epsilon": 1.0e-5},
        nodes,
        [output("out", (batch, rows, width))],
        reuse,
    )


def layout_mlp(
    opaque_id: str, batch: int, channels: int, height: int, width: int, hidden: int, reuse: int
) -> dict[str, object]:
    nodes = [
        node("x", "input", name="x"),
        node("gamma", "parameter", name="gamma"),
        node("beta", "parameter", name="beta"),
        node("w1", "parameter", name="weight_in"),
        node("b1", "parameter", name="bias_in"),
        node("w2", "parameter", name="weight_out"),
        node("b2", "parameter", name="bias_out"),
        node("nhwc", "permute", ["x"], dims=[0, 2, 3, 1]),
        node(
            "normalized",
            "layer_norm",
            ["nhwc", "gamma", "beta"],
            normalized_shape_constant="normalized_shape",
            epsilon_constant="epsilon",
        ),
        node("expanded", "linear", ["normalized", "w1", "b1"]),
        node("activated", "gelu", ["expanded"]),
        node("projected", "linear", ["activated", "w2", "b2"]),
        node("nchw", "permute", ["projected"], dims=[0, 3, 1, 2]),
        node("out", "add", ["x", "nchw"]),
    ]
    return artifact(
        opaque_id,
        [input_spec("x", (batch, channels, height, width), 0x7100 + height)],
        [
            parameter_spec("gamma", (channels,), 0x7200 + channels, init={"kind": "ones"}),
            parameter_spec("beta", (channels,), 0x7300 + channels, init={"kind": "zeros"}),
            parameter_spec("weight_in", (hidden, channels), 0x7400 + hidden),
            parameter_spec("bias_in", (hidden,), 0x7500 + hidden),
            parameter_spec("weight_out", (channels, hidden), 0x7600 + hidden),
            parameter_spec("bias_out", (channels,), 0x7700 + channels),
        ],
        {"normalized_shape": [channels], "epsilon": 1.0e-6},
        nodes,
        [output("out", (batch, channels, height, width))],
        reuse,
    )


def dense_matrix_chain(
    opaque_id: str,
    rows: int,
    inner_left: int,
    inner_right: int,
    columns: int,
    reuse: int,
) -> dict[str, object]:
    nodes = [
        node("a", "input", name="a"),
        node("b", "parameter", name="b"),
        node("c", "parameter", name="c"),
        node("ab", "matmul", ["a", "b"]),
        node("out", "matmul", ["ab", "c"]),
    ]
    return artifact(
        opaque_id,
        [input_spec("a", (rows, inner_left), 0x8100 + rows + inner_left)],
        [
            parameter_spec(
                "b",
                (inner_left, inner_right),
                0x8200 + inner_right,
                init={"kind": "normal", "scale": 0.05},
            ),
            parameter_spec(
                "c",
                (inner_right, columns),
                0x8300 + columns,
                init={"kind": "normal", "scale": 0.05},
            ),
        ],
        {},
        nodes,
        [output("out", (rows, columns))],
        reuse,
    )


def attention_projection_control(
    opaque_id: str, batch: int, tokens: int, width: int, output_width: int, reuse: int
) -> dict[str, object]:
    nodes = [node("x", "input", name="x")]
    parameters = []
    outputs = []
    for index in range(3):
        weight_name = f"weight_{index}"
        bias_name = f"bias_{index}"
        parameters.extend(
            [
                parameter_spec(
                    weight_name,
                    (output_width, width),
                    0x9100 + index * 2 + width,
                ),
                parameter_spec(
                    bias_name,
                    (output_width,),
                    0x9101 + index * 2 + output_width,
                ),
            ]
        )
        nodes.extend(
            [
                node(f"w{index}", "parameter", name=weight_name),
                node(f"b{index}", "parameter", name=bias_name),
                node(f"y{index}", "linear", ["x", f"w{index}", f"b{index}"]),
            ]
        )
        outputs.append(f"y{index}")
    nodes.append(node("out", "cat", outputs, dim=-1))
    return artifact(
        opaque_id,
        [input_spec("x", (batch, tokens, width), 0x9000 + tokens + width)],
        parameters,
        {},
        nodes,
        [output("out", (batch, tokens, 3 * output_width))],
        reuse,
    )


DEVELOPMENT_CASES = (
    ("state_space", mamba_projection, ("dev_000", 1, 8, 16, 4, 8, 1_000)),
    ("state_space", mamba_projection, ("dev_001", 2, 64, 64, 8, 16, 10_000)),
    ("state_space", mamba_projection, ("dev_002", 1, 128, 32, 4, 16, 100_000)),
    ("sparse_graph", graph_message_passing, ("dev_003", 32, 64, 8, 0.12, 2_000)),
    ("sparse_graph", graph_message_passing, ("dev_004", 64, 16, 64, 0.08, 10_000)),
    ("sparse_graph", graph_message_passing, ("dev_005", 256, 32, 16, 0.02, 50_000)),
    ("cnn", conv_batch_norm, ("dev_006", 1, 8, 16, 16, 1_000)),
    ("cnn", conv_batch_norm, ("dev_007", 1, 32, 32, 32, 10_000)),
    ("cnn", conv_batch_norm, ("dev_008", 2, 16, 64, 64, 100_000)),
    ("scientific", periodic_diffusion, ("dev_009", 1, 16, 16, 1_000)),
    ("scientific", periodic_diffusion, ("dev_010", 2, 64, 64, 10_000)),
    ("scientific", periodic_diffusion, ("dev_011", 1, 128, 128, 100_000)),
    ("normalization", explicit_normalization, ("dev_012", 1, 32, 16, 2_000)),
    ("normalization", explicit_normalization, ("dev_013", 2, 64, 64, 20_000)),
    ("normalization", explicit_normalization, ("dev_014", 4, 128, 128, 100_000)),
    ("cnn_layout", layout_mlp, ("dev_015", 1, 8, 8, 8, 32, 2_000)),
    ("cnn_layout", layout_mlp, ("dev_016", 1, 32, 16, 16, 128, 20_000)),
    ("cnn_layout", layout_mlp, ("dev_017", 2, 64, 32, 32, 256, 100_000)),
    ("dense_scientific", dense_matrix_chain, ("dev_018", 1024, 64, 512, 8, 1_000)),
    ("dense_scientific", dense_matrix_chain, ("dev_019", 8, 512, 64, 512, 10)),
    ("dense_scientific", dense_matrix_chain, ("dev_020", 64, 128, 256, 32, 100_000)),
)

VALIDATION_CASES = (
    ("state_space", mamba_projection, ("val_000", 1, 16, 24, 4, 8, 5_000)),
    ("state_space", mamba_projection, ("val_001", 2, 96, 48, 6, 12, 30_000)),
    ("state_space", mamba_projection, ("val_002", 4, 32, 96, 12, 24, 100_000)),
    ("sparse_graph", graph_message_passing, ("val_003", 128, 8, 16, 0.04, 5_000)),
    ("sparse_graph", graph_message_passing, ("val_004", 64, 48, 12, 0.06, 20_000)),
    ("sparse_graph", graph_message_passing, ("val_005", 192, 24, 48, 0.025, 80_000)),
    ("cnn", conv_batch_norm, ("val_006", 1, 12, 24, 24, 5_000)),
    ("cnn", conv_batch_norm, ("val_007", 2, 24, 40, 40, 30_000)),
    ("cnn", conv_batch_norm, ("val_008", 1, 48, 56, 56, 100_000)),
    ("scientific", periodic_diffusion, ("val_009", 1, 24, 24, 5_000)),
    ("scientific", periodic_diffusion, ("val_010", 1, 80, 80, 30_000)),
    ("scientific", periodic_diffusion, ("val_011", 2, 112, 112, 100_000)),
    ("normalization", explicit_normalization, ("val_012", 2, 64, 128, 5_000)),
    ("normalization", explicit_normalization, ("val_013", 2, 128, 128, 30_000)),
    ("normalization", explicit_normalization, ("val_014", 3, 128, 128, 100_000)),
    ("cnn_layout", layout_mlp, ("val_015", 1, 16, 12, 12, 64, 5_000)),
    ("cnn_layout", layout_mlp, ("val_016", 2, 24, 20, 20, 96, 30_000)),
    ("cnn_layout", layout_mlp, ("val_017", 1, 48, 40, 40, 192, 100_000)),
    ("dense_scientific", dense_matrix_chain, ("val_018", 512, 96, 384, 12, 5_000)),
    ("dense_scientific", dense_matrix_chain, ("val_019", 12, 384, 48, 384, 20)),
    ("dense_scientific", dense_matrix_chain, ("val_020", 96, 160, 320, 24, 50_000)),
)

CONFIRMATION_CASES = (
    ("state_space", mamba_projection, ("confirm_000", 2, 24, 40, 5, 10, 8_000)),
    ("state_space", mamba_projection, ("confirm_001", 1, 160, 80, 10, 20, 50_000)),
    ("state_space", mamba_projection, ("confirm_002", 3, 48, 56, 7, 14, 100_000)),
    ("sparse_graph", graph_message_passing, ("confirm_003", 96, 12, 24, 0.05, 8_000)),
    ("sparse_graph", graph_message_passing, ("confirm_004", 80, 40, 16, 0.04, 50_000)),
    ("sparse_graph", graph_message_passing, ("confirm_005", 160, 12, 48, 0.02, 100_000)),
    ("cnn", conv_batch_norm, ("confirm_006", 2, 10, 20, 28, 8_000)),
    ("cnn", conv_batch_norm, ("confirm_007", 1, 28, 48, 36, 50_000)),
    ("cnn", conv_batch_norm, ("confirm_008", 2, 40, 52, 60, 100_000)),
    ("scientific", periodic_diffusion, ("confirm_009", 2, 32, 32, 8_000)),
    ("scientific", periodic_diffusion, ("confirm_010", 1, 96, 72, 50_000)),
    ("scientific", periodic_diffusion, ("confirm_011", 1, 144, 96, 100_000)),
    ("normalization", explicit_normalization, ("confirm_012", 2, 80, 128, 8_000)),
    ("normalization", explicit_normalization, ("confirm_013", 2, 96, 128, 50_000)),
    ("normalization", explicit_normalization, ("confirm_014", 2, 112, 128, 100_000)),
    ("cnn_layout", layout_mlp, ("confirm_015", 2, 12, 10, 14, 48, 8_000)),
    ("cnn_layout", layout_mlp, ("confirm_016", 1, 36, 24, 20, 144, 50_000)),
    ("cnn_layout", layout_mlp, ("confirm_017", 2, 56, 36, 28, 224, 100_000)),
    ("dense_scientific", dense_matrix_chain, ("confirm_018", 768, 80, 448, 10, 8_000)),
    ("dense_scientific", dense_matrix_chain, ("confirm_019", 10, 448, 56, 448, 50)),
    ("dense_scientific", dense_matrix_chain, ("confirm_020", 80, 144, 288, 20, 80_000)),
)

PREFREEZE_CASES = (
    ("state_space", mamba_projection, ("prefreeze_000", 1, 72, 72, 9, 18, 60_000)),
    ("state_space", mamba_projection, ("prefreeze_001", 3, 20, 36, 4, 12, 12_000)),
    ("sparse_graph", graph_message_passing, ("prefreeze_002", 112, 22, 32, 0.03, 30_000)),
    ("sparse_graph", graph_message_passing, ("prefreeze_003", 112, 24, 32, 0.03, 30_000)),
    ("cnn", conv_batch_norm, ("prefreeze_004", 1, 20, 36, 44, 40_000)),
    ("cnn", conv_batch_norm, ("prefreeze_005", 2, 36, 28, 52, 80_000)),
    ("scientific", periodic_diffusion, ("prefreeze_006", 1, 48, 56, 40_000)),
    ("scientific", periodic_diffusion, ("prefreeze_007", 2, 104, 88, 80_000)),
    ("normalization", explicit_normalization, ("prefreeze_008", 1, 120, 128, 40_000)),
    ("normalization", explicit_normalization, ("prefreeze_009", 1, 144, 128, 80_000)),
    ("cnn_layout", layout_mlp, ("prefreeze_010", 1, 20, 18, 22, 80, 40_000)),
    ("cnn_layout", layout_mlp, ("prefreeze_011", 2, 44, 30, 26, 176, 80_000)),
    ("dense_scientific", dense_matrix_chain, ("prefreeze_012", 320, 96, 240, 42, 40_000)),
    ("dense_scientific", dense_matrix_chain, ("prefreeze_013", 320, 96, 240, 40, 80_000)),
    ("transformer_control", attention_projection_control, ("prefreeze_014", 1, 48, 64, 64, 40_000)),
    ("transformer_control", attention_projection_control, ("prefreeze_015", 2, 96, 96, 48, 80_000)),
)


def source_receipt(family: str) -> dict[str, object]:
    """Bind each translated family to installed source, with honest scope."""
    if family == "state_space":
        from transformers.models.mamba import modeling_mamba

        source_path = pathlib.Path(inspect.getsourcefile(modeling_mamba.MambaMixer) or "")
        source_symbol = "transformers.models.mamba.modeling_mamba.MambaMixer"
    elif family == "transformer_control":
        from transformers.models.bert import modeling_bert

        source_path = pathlib.Path(
            inspect.getsourcefile(modeling_bert.BertSelfAttention) or ""
        )
        source_symbol = (
            "transformers.models.bert.modeling_bert.BertSelfAttention"
        )
    elif family in ("cnn", "cnn_layout"):
        import torch.nn.functional

        source_path = pathlib.Path(inspect.getsourcefile(torch.nn.functional) or "")
        source_symbol = "torch.nn.functional"
    else:
        import torch

        source_path = pathlib.Path(inspect.getsourcefile(torch) or "")
        source_symbol = "torch tensor operator API"
    return {
        "source_symbol": source_symbol,
        "source_path": str(source_path),
        "source_sha256": file_sha256(source_path),
        "translation_kind": "evaluator-authored typed translation of a bounded source motif",
        "full_model_claim": False,
    }


def export_graph_receipt(payload: dict[str, object]) -> dict[str, object]:
    """Export the exact reference program module and hash its FX text."""
    import tempfile

    import torch

    from ghost_operator_core_v5 import TensorProgramModule, load_artifact, reference_plan

    with tempfile.TemporaryDirectory(prefix="ghost-operator-export-") as directory:
        path = pathlib.Path(directory) / "artifact.json"
        path.write_text(canonical_json(payload) + "\n", encoding="utf-8")
        typed, _raw = load_artifact(path)
        module, _construction = TensorProgramModule.build(typed, reference_plan(typed))
        inputs = []
        for item in typed.inputs:
            inputs.append(torch.randn(item.type.shape, dtype=torch.float32))
        try:
            exported = torch.export.export(module, tuple(inputs), strict=False)
            graph_text = str(exported.graph_module.graph)
            status = "PASS"
            error = None
        except Exception as exc:  # Sparse export is an explicit, preserved negative.
            graph_text = ""
            status = "UNSUPPORTED"
            error = f"{type(exc).__name__}: {exc}"[:500]
        return {
            "torch_version": torch.__version__,
            "torch_export_status": status,
            "torch_export_graph_sha256": hashlib.sha256(graph_text.encode()).hexdigest(),
            "torch_export_graph": graph_text,
            "torch_export_error": error,
        }


def generate(output_root: pathlib.Path, phase: str = "DEVELOPMENT") -> None:
    if phase == "DEVELOPMENT":
        cases = DEVELOPMENT_CASES
    elif phase == "VALIDATION":
        cases = VALIDATION_CASES
    elif phase == "CONFIRMATION":
        cases = CONFIRMATION_CASES
    elif phase == "PREFREEZE":
        cases = PREFREEZE_CASES
    else:
        raise ValueError(
            "corpus phase must be DEVELOPMENT, VALIDATION, CONFIRMATION, or PREFREEZE"
        )
    artifacts_dir = output_root / "artifacts"
    artifacts_dir.mkdir(parents=True, exist_ok=True)
    manifest_lines = [
        "opaque_id\tphase\tartifact_path\tartifact_sha256\tfamily\tprovenance_sha256"
    ]
    audit_rows: list[str] = []
    source_cache: dict[str, dict[str, object]] = {}
    for family, builder, args in cases:
        payload = builder(*args)
        opaque_id = payload["opaque_id"]
        path = artifacts_dir / f"{opaque_id}.json"
        path.write_text(canonical_json(payload) + "\n", encoding="utf-8")
        typed, raw = load_artifact(path)
        if typed.opaque_id != opaque_id:
            raise AssertionError("artifact id drift")
        source = source_cache.setdefault(family, source_receipt(family))
        export = export_graph_receipt(payload)
        provenance = {
            "status": "GHOST_OPERATOR_PROVENANCE_V5",
            "opaque_id": opaque_id,
            "phase": phase,
            "family": family,
            "artifact_sha256": hashlib.sha256(raw).hexdigest(),
            "source": source,
            "export": export,
        }
        provenance_sha = hashlib.sha256(canonical_json(provenance).encode()).hexdigest()
        audit_rows.append(canonical_json(provenance))
        manifest_lines.append(
            "\t".join(
                (
                    opaque_id,
                    phase,
                    str(path),
                    hashlib.sha256(raw).hexdigest(),
                    family,
                    provenance_sha,
                )
            )
        )
        print(
            f"GHOST_OPERATOR_CORPUS_V5 artifact={opaque_id} family={family}"
            f" export={export['torch_export_status']}"
        )
    manifest = output_root / "manifest.tsv"
    audit = output_root / "provenance.private.jsonl"
    manifest.write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")
    audit.write_text("\n".join(audit_rows) + "\n", encoding="utf-8")
    print(
        "GHOST_OPERATOR_CORPUS_V5 PASS"
        f" phase={phase} artifacts={len(cases)}"
        f" manifest_sha256={file_sha256(manifest)}"
        f" provenance_sha256={file_sha256(audit)}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output_root", type=pathlib.Path)
    parser.add_argument("--phase", default="DEVELOPMENT")
    args = parser.parse_args()
    generate(args.output_root, args.phase)


if __name__ == "__main__":
    main()
