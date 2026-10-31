#!/usr/bin/env python3
"""Isolated constructors for the unchanged frozen v2 workloads."""

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


def constructors():
    torch.manual_seed(SEED)

    def rnn():
        module = load("foundry_v2_rnn", SOURCES / "mnist_rnn_model.py")
        return {
            "family": "recurrent_image_classification",
            "model": module.Net().eval(),
            "args": (torch.randn(4, 1, 28, 28),),
            "kwargs": {},
        }

    def reinforce():
        module = load("foundry_v2_reinforce", SOURCES / "reinforce_model.py")
        return {
            "family": "policy_gradient_control",
            "model": module.Policy().eval(),
            "args": (torch.randn(8, 4),),
            "kwargs": {},
        }

    def gcn():
        module = load("foundry_v2_gcn", SOURCES / "gcn_model.py")
        return {
            "family": "graph_node_classification",
            "model": module.GCN(8, 16, 3, use_bias=True, dropout_p=0.1).eval(),
            "args": (torch.randn(16, 8), torch.eye(16).to_sparse()),
            "kwargs": {},
        }

    def siamese():
        module = load("foundry_v2_siamese", SOURCES / "siamese_model.py")
        return {
            "family": "siamese_image_comparison",
            "model": module.SiameseNetwork().eval(),
            "args": (
                torch.randn(2, 1, 64, 64),
                torch.randn(2, 1, 64, 64),
            ),
            "kwargs": {},
        }

    return [
        ("recurrent_image_classification", rnn),
        ("policy_gradient_control", reinforce),
        ("graph_node_classification", gcn),
        ("siamese_image_comparison", siamese),
    ]
