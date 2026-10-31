"""Model-only adaptation of pytorch/examples regression/main.py."""

import torch
import torch.nn.functional as F


POLY_DEGREE = 4


def make_features(x):
    """Builds features i.e. a matrix with columns [x, x^2, x^3, x^4]."""
    x = x.unsqueeze(1)
    return torch.cat([x ** i for i in range(1, POLY_DEGREE+1)], 1)


class PolynomialRegressor(torch.nn.Module):
    """Harness module around the upstream feature construction and linear fit."""

    def __init__(self):
        super().__init__()
        self.fc = torch.nn.Linear(POLY_DEGREE, 1)

    def forward(self, x, target):
        features = make_features(x)
        prediction = self.fc(features)
        return F.smooth_l1_loss(prediction, target)
