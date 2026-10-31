#!/usr/bin/env python3
"""Construct the frozen v5 validation workloads without executing them."""

from __future__ import annotations

import torch

from external_validation_v5.models import (
    Autoencoder,
    RNNLM,
    TutorialNet,
    two_layer_regression,
)


def instantiate() -> list[dict[str, object]]:
    torch.manual_seed(5305)
    recurrent = RNNLM(64, 16, 32, 1).eval()
    hidden = (
        torch.zeros(1, 3, 32),
        torch.zeros(1, 3, 32),
    )
    return [
        {
            "family": "two_layer_nonlinear_regression",
            "semantic_domain": "regression",
            "repository": "jcjohnson/pytorch-examples",
            "model": two_layer_regression().eval(),
            "args": (torch.randn(8, 1000),),
            "kwargs": {},
        },
        {
            "family": "lenet_image_classification",
            "semantic_domain": "image_classification",
            "repository": "pytorch/tutorials",
            "model": TutorialNet().eval(),
            "args": (torch.randn(2, 1, 32, 32),),
            "kwargs": {},
        },
        {
            "family": "lstm_language_model",
            "semantic_domain": "sequence_language_modeling",
            "repository": "yunjey/pytorch-tutorial",
            "model": recurrent,
            "args": (torch.randint(0, 64, (3, 5)), hidden),
            "kwargs": {},
        },
        {
            "family": "linear_image_autoencoder",
            "semantic_domain": "representation_learning",
            "repository": "udacity/deep-learning-v2-pytorch",
            "model": Autoencoder(32).eval(),
            "args": (torch.rand(8, 28 * 28),),
            "kwargs": {},
        },
    ]
