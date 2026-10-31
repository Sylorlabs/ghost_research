#!/usr/bin/env python3
"""Independent schema construction for the adapted A1 fold bridge."""

from __future__ import annotations

import hashlib
import json
import math
from typing import Any

import torch
from torch.fx import GraphModule, Node


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def pair(value: Any, label: str) -> list[int]:
    if type(value) is int:
        values = [value, value]
    elif isinstance(value, (tuple, list)) and len(value) == 2:
        values = list(value)
    else:
        raise ValueError(f"{label} is not a pair")
    if any(type(item) is not int for item in values):
        raise ValueError(f"{label} contains a non-integer")
    return values


def tensor_type(value: Any) -> dict[str, object]:
    if not isinstance(value, torch.Tensor):
        raise ValueError("expected tensor metadata")
    if value.dtype != torch.float32:
        raise ValueError("only float32 is admitted")
    return {
        "shape": list(value.shape),
        "dtype": "float32",
        "storage": "strided",
    }


def seed(label: str) -> str:
    value = int.from_bytes(hashlib.sha256(label.encode()).digest()[:8], "big")
    return hex(value % (2**63))


def compare(
    expected: torch.Tensor,
    actual: torch.Tensor,
    source_input: torch.Tensor,
    *,
    tolerance: float,
) -> dict[str, object]:
    """Independently enforce the frozen value, metadata, and storage contract."""
    if not all(
        isinstance(value, torch.Tensor)
        for value in (expected, actual, source_input)
    ):
        raise ValueError("comparison boundary is not tensor-only")
    if (
        expected.shape != actual.shape
        or expected.dtype != actual.dtype
        or expected.device != actual.device
        or expected.layout != actual.layout
        or expected.stride() != actual.stride()
        or expected.storage_offset() != actual.storage_offset()
    ):
        raise ValueError("tensor metadata mismatch")
    error = float((expected.detach() - actual.detach()).abs().max().item())
    if not math.isfinite(error) or error > tolerance:
        raise ValueError("tensor value tolerance exceeded")
    expected_bytes = expected.untyped_storage().nbytes()
    actual_bytes = actual.untyped_storage().nbytes()
    if expected_bytes != actual_bytes:
        raise ValueError("storage extent mismatch")
    source_pointer = source_input.untyped_storage().data_ptr()
    expected_pointer = expected.untyped_storage().data_ptr()
    actual_pointer = actual.untyped_storage().data_ptr()
    if (
        expected_pointer == actual_pointer
        or source_pointer == expected_pointer
        or source_pointer == actual_pointer
    ):
        raise ValueError("unexpected output alias")
    return {
        "max_abs_error": error,
        "metadata_checks_passed": True,
        "alias_checks_passed": True,
        "storage_extent_bytes": actual_bytes,
    }


def lower(
    module: GraphModule,
    artifact_id: str,
    conv_name: str,
    batch_name: str,
) -> dict[str, object]:
    nodes = {node.name: node for node in module.graph.nodes}
    conv = nodes[conv_name]
    batch = nodes[batch_name]
    if (
        conv.op != "call_function"
        or str(conv.target) != "aten.conv2d.default"
        or batch.op != "call_function"
        or str(batch.target)
        != "aten._native_batch_norm_legit_no_training.default"
        or len(batch.args) != 7
        or batch.args[0] is not conv
    ):
        raise ValueError("source pattern mismatch")
    if len(conv.args) < 2 or len(conv.args) > 7:
        raise ValueError("conv signature mismatch")
    x = conv.args[0]
    weight = conv.args[1]
    bias = conv.args[2] if len(conv.args) >= 3 else None
    if not isinstance(x, Node) or not isinstance(weight, Node):
        raise ValueError("conv tensor boundaries")
    gamma, beta, mean, variance = batch.args[1:5]
    if not all(isinstance(value, Node) for value in (gamma, beta, mean, variance)):
        raise ValueError("batchnorm parameter boundaries")
    momentum, epsilon = batch.args[5:7]
    if type(momentum) not in {int, float} or type(epsilon) not in {int, float}:
        raise ValueError("batchnorm constants")
    stride = pair(conv.args[3] if len(conv.args) >= 4 else 1, "stride")
    padding = pair(conv.args[4] if len(conv.args) >= 5 else 0, "padding")
    dilation = pair(conv.args[5] if len(conv.args) >= 6 else 1, "dilation")
    groups = conv.args[6] if len(conv.args) >= 7 else 1
    if type(groups) is not int or groups <= 0:
        raise ValueError("groups")
    x_type = tensor_type(x.meta.get("val"))
    weight_type = tensor_type(weight.meta.get("val"))
    channel_type = tensor_type(gamma.meta.get("val"))
    for value in (beta, mean, variance):
        if tensor_type(value.meta.get("val")) != channel_type:
            raise ValueError("batchnorm parameter type disagreement")
    channels = channel_type["shape"][0]
    if weight_type["shape"][0] != channels:
        raise ValueError("conv output channels")
    if bias is not None:
        if not isinstance(bias, Node) or tensor_type(bias.meta.get("val")) != channel_type:
            raise ValueError("conv bias")
    output_meta = batch.meta.get("val")
    if not isinstance(output_meta, (tuple, list)) or not output_meta:
        raise ValueError("native batchnorm output metadata")
    output_type = tensor_type(output_meta[0])
    identity = canonical(
        {
            "artifact_id": artifact_id,
            "conv": conv_name,
            "batch": batch_name,
            "input": x_type,
            "weight": weight_type,
            "channel": channel_type,
            "output": output_type,
            "stride": stride,
            "padding": padding,
            "dilation": dilation,
            "groups": groups,
            "epsilon": float(epsilon),
        }
    )
    opaque_id = "a1_fold_" + hashlib.sha256(identity.encode()).hexdigest()[:20]
    inputs = [{"name": "i0", "type": x_type, "seed_hex": seed(identity + ":i0")}]
    parameter_types = [
        weight_type,
        channel_type,
        channel_type,
        channel_type,
        channel_type,
        channel_type,
    ]
    inits = [
        {"kind": "normal", "scale": 0.2},
        {"kind": "zeros"} if bias is None else {"kind": "normal", "scale": 0.2},
        {"kind": "normal", "scale": 0.1},
        {"kind": "normal", "scale": 0.2},
        {"kind": "normal", "scale": 0.2},
        {"kind": "positive", "scale": 0.3, "offset": 0.5},
    ]
    parameters = [
        {
            "name": f"p{index}",
            "type": spec_type,
            "seed_hex": seed(identity + f":p{index}"),
            "init": init,
        }
        for index, (spec_type, init) in enumerate(
            zip(parameter_types, inits, strict=True)
        )
    ]
    nodes_out = [
        {"id": "n0", "op": "input", "args": [], "attrs": {"name": "i0"}},
        *[
            {
                "id": f"n{index + 1}",
                "op": "parameter",
                "args": [],
                "attrs": {"name": f"p{index}"},
            }
            for index in range(6)
        ],
        {
            "id": "n7",
            "op": "conv2d",
            "args": ["n0", "n1", "n2"],
            "attrs": {
                "stride": stride,
                "padding": padding,
                "dilation": dilation,
                "groups": groups,
            },
        },
        {
            "id": "n8",
            "op": "batch_norm_eval",
            "args": ["n7", "n3", "n4", "n5", "n6"],
            "attrs": {"epsilon_constant": "c0"},
        },
    ]
    return {
        "version": "GHOST_OPERATOR_ARTIFACT_V5",
        "opaque_id": opaque_id,
        "inputs": inputs,
        "parameters": parameters,
        "constants": {
            "c0": float(epsilon),
            "c1": [channels, 1, 1, 1],
        },
        "reference_program": {"nodes": nodes_out, "outputs": ["n8"]},
        "outputs": [
            {
                "value": "n8",
                "type": output_type,
                "layout": "last_dim_stride_1",
            }
        ],
        "reuse_calls": 3,
    }
