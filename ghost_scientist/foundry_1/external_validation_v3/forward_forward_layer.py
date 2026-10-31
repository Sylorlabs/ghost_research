"""Forward-only adapter of Layer from mnist_forward_forward/main.py."""

import torch
import torch.nn as nn


class Layer(nn.Linear):
    def __init__(self, in_features, out_features, bias=True):
        super().__init__(in_features, out_features, bias)
        self.relu = nn.ReLU()

    def forward(self, x):
        x_direction = x / (x.norm(2, 1, keepdim=True) + 1e-4)
        return self.relu(
            torch.mm(x_direction, self.weight.T) + self.bias.unsqueeze(0)
        )
