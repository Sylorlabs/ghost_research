"""Model-only snapshot from pytorch/examples distributed/rpc/rnn/rnn.py."""

import torch.nn as nn


class Decoder(nn.Module):
    def __init__(self, ntoken, nhid, dropout):
        super().__init__()
        self.drop = nn.Dropout(dropout)
        self.decoder = nn.Linear(nhid, ntoken)
        nn.init.zeros_(self.decoder.bias)
        nn.init.uniform_(self.decoder.weight, -0.1, 0.1)

    def forward(self, output):
        return self.decoder(self.drop(output))
