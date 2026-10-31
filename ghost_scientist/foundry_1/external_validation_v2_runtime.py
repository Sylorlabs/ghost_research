#!/usr/bin/env python3
"""Frozen runtime harness for the Foundry ATen prospective component."""

from __future__ import annotations

import importlib.util
import pathlib

import torch


HERE = pathlib.Path(__file__).resolve().parent
SOURCES = HERE / "external_validation_v2"
SEED = 0xF02D2026


def load(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def instantiate():
    torch.manual_seed(SEED)
    rnn = load("foundry_v2_rnn", SOURCES / "mnist_rnn_model.py")
    reinforce = load("foundry_v2_reinforce", SOURCES / "reinforce_model.py")
    gcn = load("foundry_v2_gcn", SOURCES / "gcn_model.py")
    siamese = load("foundry_v2_siamese", SOURCES / "siamese_model.py")
    adjacency = torch.eye(16).to_sparse()
    return [
        {
            "family": "recurrent_image_classification",
            "model": rnn.Net().eval(),
            "args": (torch.randn(4, 1, 28, 28),),
            "kwargs": {},
        },
        {
            "family": "policy_gradient_control",
            "model": reinforce.Policy().eval(),
            "args": (torch.randn(8, 4),),
            "kwargs": {},
        },
        {
            "family": "graph_node_classification",
            "model": gcn.GCN(8, 16, 3, use_bias=True, dropout_p=0.1).eval(),
            "args": (torch.randn(16, 8), adjacency),
            "kwargs": {},
        },
        {
            "family": "siamese_image_comparison",
            "model": siamese.SiameseNetwork().eval(),
            "args": (
                torch.randn(2, 1, 64, 64),
                torch.randn(2, 1, 64, 64),
            ),
            "kwargs": {},
        },
    ]
