"""Licensed source-faithful model excerpts for the frozen v5 intake.

Only batch sizes and constructor arguments are supplied by the local harness.
Layer order, operators, and forward dataflow match the pinned upstream sources
recorded in SOURCE_INTAKE.json. No Transformer or attention model is present.
"""

from __future__ import annotations

import torch
import torch.nn as nn
import torch.nn.functional as F


def two_layer_regression() -> nn.Module:
    """jcjohnson/pytorch-examples two-layer nonlinear regression network."""

    return nn.Sequential(
        nn.Linear(1000, 100),
        nn.ReLU(),
        nn.Linear(100, 10),
    )


class TutorialNet(nn.Module):
    """pytorch/tutorials digit-image convolutional classifier."""

    def __init__(self) -> None:
        super().__init__()
        self.conv1 = nn.Conv2d(1, 6, 5)
        self.conv2 = nn.Conv2d(6, 16, 5)
        self.fc1 = nn.Linear(16 * 5 * 5, 120)
        self.fc2 = nn.Linear(120, 84)
        self.fc3 = nn.Linear(84, 10)

    def forward(self, input: torch.Tensor) -> torch.Tensor:
        c1 = F.relu(self.conv1(input))
        s2 = F.max_pool2d(c1, (2, 2))
        c3 = F.relu(self.conv2(s2))
        s4 = F.max_pool2d(c3, 2)
        s4 = torch.flatten(s4, 1)
        f5 = F.relu(self.fc1(s4))
        f6 = F.relu(self.fc2(f5))
        return self.fc3(f6)


class RNNLM(nn.Module):
    """yunjey/pytorch-tutorial recurrent language model."""

    def __init__(
        self,
        vocab_size: int,
        embed_size: int,
        hidden_size: int,
        num_layers: int,
    ) -> None:
        super().__init__()
        self.embed = nn.Embedding(vocab_size, embed_size)
        self.lstm = nn.LSTM(
            embed_size, hidden_size, num_layers, batch_first=True
        )
        self.linear = nn.Linear(hidden_size, vocab_size)

    def forward(
        self,
        x: torch.Tensor,
        h: tuple[torch.Tensor, torch.Tensor],
    ) -> tuple[torch.Tensor, tuple[torch.Tensor, torch.Tensor]]:
        x = self.embed(x)
        out, (h, c) = self.lstm(x, h)
        out = out.reshape(out.size(0) * out.size(1), out.size(2))
        out = self.linear(out)
        return out, (h, c)


class Autoencoder(nn.Module):
    """Udacity linear image autoencoder."""

    def __init__(self, encoding_dim: int) -> None:
        super().__init__()
        self.fc1 = nn.Linear(28 * 28, encoding_dim)
        self.fc2 = nn.Linear(encoding_dim, 28 * 28)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = F.relu(self.fc1(x))
        x = F.sigmoid(self.fc2(x))
        return x
