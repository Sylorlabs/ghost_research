#!/usr/bin/env python3
"""Post-forge calibration harness for the preselected external validation sources."""

from __future__ import annotations

import importlib.util
import pathlib

import torch

from freeze_external_validation_v1 import verify


HERE = pathlib.Path(__file__).resolve().parent
SOURCES = HERE / "external_validation_v1"


def load(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def instantiate():
    verify()
    torch.manual_seed(0xA7E1)
    regression = load("foundry_val_regression", SOURCES / "regression_model.py")
    policy = load("foundry_val_policy", SOURCES / "actor_critic_model.py")
    dcgan = load("foundry_val_dcgan", SOURCES / "dcgan_model.py")
    style = load("foundry_val_style", SOURCES / "neural_style_model.py")
    regression_x = torch.randn(32)
    regression_target = torch.randn(32, 1)
    return [
        {
            "family": "polynomial_regression",
            "model": regression.PolynomialRegressor().eval(),
            "args": (regression_x, regression_target),
            "kwargs": {},
        },
        {
            "family": "actor_critic_control",
            "model": policy.Policy().eval(),
            "args": (torch.randn(8, 4),),
            "kwargs": {},
        },
        {
            "family": "adversarial_image_generation",
            "model": dcgan.Discriminator(1).eval(),
            "args": (torch.randn(1, 3, 64, 64),),
            "kwargs": {},
        },
        {
            "family": "convolutional_style_transfer",
            "model": style.TransformerNet().eval(),
            "args": (torch.randn(1, 3, 32, 32),),
            "kwargs": {},
        },
    ]
