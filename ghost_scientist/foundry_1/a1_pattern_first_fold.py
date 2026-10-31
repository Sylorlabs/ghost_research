#!/usr/bin/env python3
"""Primary typed lowerer and execution helpers for adapted A1 folds."""

from __future__ import annotations

import copy
import hashlib
import inspect
import json
import pathlib
import sys
from typing import Any

import torch
import torch.nn.functional as functional
from torch.fx import GraphModule, Interpreter, Node

from independent_framework_runtime import clone_tree


HERE = pathlib.Path(__file__).resolve().parent
OPERATOR = (HERE / "../operator_v5").resolve()
if str(OPERATOR) not in sys.path:
    sys.path.insert(0, str(OPERATOR))

from ghost_operator_candidate_v5 import (  # noqa: E402
    construct,
    enumerate_plans as candidate_enumerate,
    structural_signature,
)
from ghost_operator_core_v5 import (  # noqa: E402
    canonical_json,
    load_artifact,
    load_plan_text,
    measure_plan,
    sha256_json,
)
from ghost_operator_corpus_v5 import (  # noqa: E402
    artifact,
    input_spec,
    node,
    output,
    parameter_spec,
)
from ghost_operator_synthesis_v5 import (  # noqa: E402
    enumerate_plans as evaluator_enumerate,
)


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def pair(value: Any, label: str) -> list[int]:
    if type(value) is int:
        output = [value, value]
    elif isinstance(value, (tuple, list)) and len(value) == 2:
        output = list(value)
    else:
        raise ValueError(f"{label} is not a pair")
    if any(type(item) is not int for item in output):
        raise ValueError(f"{label} contains non-integer")
    return output


def meta_tensor(node: Node) -> torch.Tensor:
    value = node.meta.get("val")
    if not isinstance(value, torch.Tensor) or value.dtype != torch.float32:
        raise ValueError(f"{node.name} tensor metadata unsupported")
    return value


def descriptor(
    module: GraphModule,
    artifact_id: str,
    conv_name: str,
    batch_name: str,
) -> dict[str, Any]:
    nodes = {node.name: node for node in module.graph.nodes}
    conv = nodes.get(conv_name)
    batch = nodes.get(batch_name)
    if conv is None or batch is None:
        raise ValueError("target node absent")
    if not (
        conv.op == "call_function"
        and str(conv.target) == "aten.conv2d.default"
        and batch.op == "call_function"
        and str(batch.target)
        == "aten._native_batch_norm_legit_no_training.default"
        and len(batch.args) == 7
        and batch.args[0] is conv
    ):
        raise ValueError("target pattern mismatch")
    x, weight = conv.args[:2]
    bias = conv.args[2] if len(conv.args) >= 3 else None
    gamma, beta, mean, variance = batch.args[1:5]
    if not all(
        isinstance(value, Node)
        for value in (x, weight, gamma, beta, mean, variance)
    ):
        raise ValueError("typed boundary is not node-backed")
    stride = pair(conv.args[3] if len(conv.args) >= 4 else 1, "stride")
    padding = pair(conv.args[4] if len(conv.args) >= 5 else 0, "padding")
    dilation = pair(conv.args[5] if len(conv.args) >= 6 else 1, "dilation")
    groups = conv.args[6] if len(conv.args) >= 7 else 1
    if type(groups) is not int or groups <= 0:
        raise ValueError("groups")
    epsilon = batch.args[6]
    if type(epsilon) not in {int, float} or not 0.0 < float(epsilon) < 1.0:
        raise ValueError("epsilon")
    output_meta = batch.meta.get("val")
    if not isinstance(output_meta, (tuple, list)) or not output_meta:
        raise ValueError("batchnorm output")
    values = {
        "x": meta_tensor(x),
        "weight": meta_tensor(weight),
        "gamma": meta_tensor(gamma),
        "beta": meta_tensor(beta),
        "mean": meta_tensor(mean),
        "variance": meta_tensor(variance),
        "output": output_meta[0],
    }
    if not isinstance(values["output"], torch.Tensor):
        raise ValueError("batchnorm tensor output")
    channels = values["gamma"].shape[0]
    if not (
        values["weight"].shape[0] == channels
        and all(
            value.shape == torch.Size([channels])
            for value in (
                values["gamma"],
                values["beta"],
                values["mean"],
                values["variance"],
            )
        )
    ):
        raise ValueError("channel relations")
    if bias is not None:
        if not isinstance(bias, Node) or meta_tensor(bias).shape != torch.Size(
            [channels]
        ):
            raise ValueError("conv bias")
    return {
        "artifact_id": artifact_id,
        "conv_name": conv_name,
        "batch_name": batch_name,
        "conv": conv,
        "batch": batch,
        "x": x,
        "weight": weight,
        "bias": bias,
        "gamma": gamma,
        "beta": beta,
        "mean": mean,
        "variance": variance,
        "stride": stride,
        "padding": padding,
        "dilation": dilation,
        "groups": groups,
        "epsilon": float(epsilon),
        "channels": channels,
        "values": values,
    }


def primary_lower(desc: dict[str, Any]) -> dict[str, object]:
    values = desc["values"]
    typed = {
        name: {
            "shape": list(value.shape),
            "dtype": "float32",
            "storage": "strided",
        }
        for name, value in values.items()
    }
    identity = canonical(
        {
            "artifact_id": desc["artifact_id"],
            "conv": desc["conv_name"],
            "batch": desc["batch_name"],
            "input": typed["x"],
            "weight": typed["weight"],
            "channel": typed["gamma"],
            "output": typed["output"],
            "stride": desc["stride"],
            "padding": desc["padding"],
            "dilation": desc["dilation"],
            "groups": desc["groups"],
            "epsilon": desc["epsilon"],
        }
    )
    seed_value = lambda label: int.from_bytes(  # noqa: E731
        hashlib.sha256((identity + label).encode()).digest()[:8], "big"
    ) % (2**63)
    nodes = [
        node("x", "input", name="x"),
        node("weight", "parameter", name="weight"),
        node("bias", "parameter", name="bias"),
        node("gamma", "parameter", name="gamma"),
        node("beta", "parameter", name="beta"),
        node("mean", "parameter", name="mean"),
        node("variance", "parameter", name="variance"),
        node(
            "conv",
            "conv2d",
            ["x", "weight", "bias"],
            stride=desc["stride"],
            padding=desc["padding"],
            dilation=desc["dilation"],
            groups=desc["groups"],
        ),
        node(
            "bn",
            "batch_norm_eval",
            ["conv", "gamma", "beta", "mean", "variance"],
            epsilon_constant="epsilon",
        ),
    ]
    channel_shape = tuple(values["gamma"].shape)
    return artifact(
        "a1_fold_" + hashlib.sha256(identity.encode()).hexdigest()[:20],
        [input_spec("x", tuple(values["x"].shape), seed_value(":i0"))],
        [
            parameter_spec(
                "weight", tuple(values["weight"].shape), seed_value(":p0")
            ),
            parameter_spec(
                "bias",
                channel_shape,
                seed_value(":p1"),
                init=(
                    {"kind": "zeros"}
                    if desc["bias"] is None
                    else {"kind": "normal", "scale": 0.2}
                ),
            ),
            parameter_spec(
                "gamma",
                channel_shape,
                seed_value(":p2"),
                init={"kind": "normal", "scale": 0.1},
            ),
            parameter_spec("beta", channel_shape, seed_value(":p3")),
            parameter_spec("mean", channel_shape, seed_value(":p4")),
            parameter_spec(
                "variance",
                channel_shape,
                seed_value(":p5"),
                init={"kind": "positive", "scale": 0.3, "offset": 0.5},
            ),
        ],
        {
            "epsilon": desc["epsilon"],
            "channel_scale_shape": [desc["channels"], 1, 1, 1],
        },
        nodes,
        [output("bn", tuple(values["output"].shape))],
        3,
    )


class Capture(Interpreter):
    def __init__(self, module: GraphModule):
        super().__init__(module)
        self.values: dict[str, Any] = {}

    def run_node(self, node: Node) -> Any:
        value = super().run_node(node)
        self.values[node.name] = value
        return value


def capture(module: GraphModule, args, kwargs) -> dict[str, Any]:
    bound = inspect.signature(module.forward).bind(
        *clone_tree(args), **clone_tree(kwargs)
    )
    bound.apply_defaults()
    runner = Capture(module)
    with torch.no_grad():
        runner.run(*bound.arguments.values())
    return runner.values


def folded_actual(desc: dict[str, Any], captures: dict[str, Any]) -> torch.Tensor:
    get = lambda node: captures[node.name]  # noqa: E731
    x = get(desc["x"])
    weight = get(desc["weight"])
    bias = (
        torch.zeros(
            weight.shape[0], dtype=weight.dtype, device=weight.device
        )
        if desc["bias"] is None
        else get(desc["bias"])
    )
    gamma = get(desc["gamma"])
    beta = get(desc["beta"])
    mean = get(desc["mean"])
    variance = get(desc["variance"])
    scale = gamma * torch.rsqrt(variance + desc["epsilon"])
    folded_weight = weight * scale.reshape(-1, 1, 1, 1)
    folded_bias = (bias - mean) * scale + beta
    return functional.conv2d(
        x,
        folded_weight,
        folded_bias,
        stride=desc["stride"],
        padding=desc["padding"],
        dilation=desc["dilation"],
        groups=desc["groups"],
    )


def extend_grammar(
    original: dict[str, Any], signature: str
) -> dict[str, Any]:
    if signature in original["rules"]:
        raise ValueError("extension signature already exists")
    adapted = copy.deepcopy(original)
    adapted["rules"][signature] = {"kind": "leaf", "plan_index": 1}
    return adapted


def verify_extension(
    original: dict[str, Any], adapted: dict[str, Any], signature: str
) -> None:
    if set(adapted) != set(original):
        raise ValueError("grammar top fields changed")
    if adapted["version"] != original["version"]:
        raise ValueError("grammar version changed")
    if set(adapted["rules"]) != set(original["rules"]) | {signature}:
        raise ValueError("grammar rule keys changed")
    if any(
        adapted["rules"][key] != value
        for key, value in original["rules"].items()
    ):
        raise ValueError("existing grammar decision changed")
    if adapted["rules"][signature] != {"kind": "leaf", "plan_index": 1}:
        raise ValueError("extension decision changed")


def v5_execute(
    payload: dict[str, object],
    original: dict[str, Any],
    signature_expected: str,
    artifact_path: pathlib.Path,
) -> dict[str, Any]:
    artifact_path.write_text(canonical_json(payload) + "\n")
    parsed, raw = load_artifact(artifact_path)
    signature = hashlib.sha256(
        structural_signature(payload).encode()
    ).hexdigest()
    if signature != signature_expected:
        raise ValueError("translated structural signature changed")
    candidate_plans = candidate_enumerate(payload)
    evaluator_plans = evaluator_enumerate(parsed)
    if canonical(candidate_plans) != canonical(evaluator_plans):
        raise ValueError("candidate/evaluator plan enumeration differs")
    adapted = extend_grammar(original, signature)
    verify_extension(original, adapted, signature)
    original_plan = construct(payload, original)
    adapted_plan = construct(payload, adapted)
    original_index = candidate_plans.index(original_plan)
    adapted_index = candidate_plans.index(adapted_plan)
    if original_index != 0 or adapted_index != 1:
        raise ValueError("grammar selection relation failed")
    loaded_plan = load_plan_text(canonical_json(adapted_plan), parsed)
    metrics = measure_plan(
        parsed,
        loaded_plan,
        backend="eager",
        repetitions=3,
        inner_iterations=2,
    )
    return {
        "artifact_sha256": hashlib.sha256(raw).hexdigest(),
        "structural_signature_sha256": signature,
        "candidate_plan_count": len(candidate_plans),
        "evaluator_plan_count": len(evaluator_plans),
        "plan_set_sha256": sha256_json(candidate_plans),
        "original_grammar_plan_index": original_index,
        "adapted_grammar_plan_index": adapted_index,
        "adapted_plan_sha256": sha256_json(adapted_plan),
        "metrics": metrics,
    }
