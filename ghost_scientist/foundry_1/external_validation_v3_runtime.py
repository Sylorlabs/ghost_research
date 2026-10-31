#!/usr/bin/env python3
"""Pre-forge-frozen runtime harness for semantic-tool validation."""

from __future__ import annotations

import importlib.util
import pathlib

import torch


HERE = pathlib.Path(__file__).resolve().parent
SOURCES = HERE / "external_validation_v3"
SEED = 0x5E6A2026


def load(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def instantiate():
    torch.manual_seed(SEED)
    hogwild = load("foundry_v3_hogwild", SOURCES / "hogwild_model.py")
    forward = load("foundry_v3_forward", SOURCES / "forward_forward_layer.py")
    ddp = load("foundry_v3_ddp", SOURCES / "ddp_toy_model.py")
    decoder = load("foundry_v3_decoder", SOURCES / "rpc_decoder_model.py")
    return [
        {
            "family": "multiprocess_image_classification",
            "model": hogwild.Net().eval(),
            "args": (torch.randn(4, 1, 28, 28),),
            "kwargs": {},
        },
        {
            "family": "forward_forward_local_learning",
            "model": forward.Layer(20, 12).eval(),
            "args": (torch.randn(8, 20),),
            "kwargs": {},
        },
        {
            "family": "distributed_data_parallel_toy",
            "model": ddp.ToyModel().eval(),
            "args": (torch.randn(8, 10),),
            "kwargs": {},
        },
        {
            "family": "remote_recurrent_decoder",
            "model": decoder.Decoder(13, 7, 0.2).eval(),
            "args": (torch.randn(5, 4, 7),),
            "kwargs": {},
        },
    ]
