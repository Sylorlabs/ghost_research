#!/usr/bin/env python3
"""Construct the frozen v6 validation workloads without executing them."""

from __future__ import annotations

import random

import torch

from external_validation_v6.models import (
    BilinearNet,
    Decoder,
    Encoder,
    Seq2Seq,
    TemporalConvNet,
    UNet,
)


def instantiate() -> list[dict[str, object]]:
    torch.manual_seed(6306)
    random.seed(6306)
    encoder = Encoder(40, 8, 16, 2, 0.0)
    decoder = Decoder(45, 8, 16, 2, 0.0)
    translator = Seq2Seq(encoder, decoder, torch.device("cpu")).eval()
    return [
        {
            "family": "unet_brain_segmentation",
            "semantic_domain": "dense_image_segmentation",
            "repository": "mateuszbuda/brain-segmentation-pytorch",
            "model": UNet(3, 1, init_features=4).eval(),
            "args": (torch.randn(1, 3, 32, 32),),
            "kwargs": {},
        },
        {
            "family": "recurrent_sequence_translation",
            "semantic_domain": "sequence_to_sequence_translation",
            "repository": "bentrevett/pytorch-seq2seq",
            "model": translator,
            "args": (
                torch.randint(0, 40, (5, 2)),
                torch.randint(0, 45, (6, 2)),
                1.0,
            ),
            "kwargs": {},
        },
        {
            "family": "bilinear_implicit_recommendation",
            "semantic_domain": "recommendation_ranking",
            "repository": "maciejkula/spotlight",
            "model": BilinearNet(32, 64, 8).eval(),
            "args": (
                torch.randint(0, 32, (8, 1)),
                torch.randint(0, 64, (8, 1)),
            ),
            "kwargs": {},
        },
        {
            "family": "dilated_temporal_convolution",
            "semantic_domain": "temporal_sequence_modeling",
            "repository": "locuslab/TCN",
            "model": TemporalConvNet(3, [4, 4], 3, 0.0).eval(),
            "args": (torch.randn(2, 3, 16),),
            "kwargs": {},
        },
    ]
