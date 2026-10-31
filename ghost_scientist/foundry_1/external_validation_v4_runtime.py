#!/usr/bin/env python3
"""Pre-forge-frozen runtime for polymorphic semantic-tool validation."""

from __future__ import annotations

import importlib.util
import pathlib

import torch


HERE = pathlib.Path(__file__).resolve().parent
SOURCES = HERE / "external_validation_v4"
SEED = 0xC0572026


def load(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def instantiate():
    torch.manual_seed(SEED)
    health = load("foundry_v4_health", SOURCES / "pyhealth_graph_model.py")
    robust = load("foundry_v4_robust", SOURCES / "deeprobust_gaussian_model.py")
    parameter = load(
        "foundry_v4_parameter", SOURCES / "parameter_server_model.py"
    )
    linear = load(
        "foundry_v4_linear", SOURCES / "distributed_linear_model.py"
    )
    dense_adj = torch.eye(10)
    return [
        {
            "family": "healthcare_dense_graph_convolution",
            "model": health.GraphConvolution(8, 6).eval(),
            "args": (torch.randn(10, 8), dense_adj),
            "kwargs": {},
        },
        {
            "family": "robust_gaussian_graph_convolution",
            "model": robust.GGCL_F(8, 6, dropout=0.0).eval(),
            "args": (
                torch.randn(10, 8),
                torch.eye(10),
                torch.eye(10),
            ),
            "kwargs": {},
        },
        {
            "family": "parameter_server_image_classification",
            "model": parameter.Net().eval(),
            "args": (torch.randn(4, 1, 28, 28),),
            "kwargs": {},
        },
        {
            "family": "distributed_linear_training_job",
            "model": linear.LinearJob().eval(),
            "args": (torch.randn(16, 20),),
            "kwargs": {},
        },
    ]
