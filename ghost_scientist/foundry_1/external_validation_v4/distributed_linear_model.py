"""Model adapter from the Linear(20, 1) DDP tutorial training job."""

import torch.nn as nn


class LinearJob(nn.Module):
    def __init__(self):
        super().__init__()
        self.model = nn.Linear(20, 1)

    def forward(self, source):
        return self.model(source)
