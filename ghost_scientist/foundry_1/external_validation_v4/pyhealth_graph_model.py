"""GraphConvolution slice from sunlabuiuc/PyHealth."""

import math

import torch
import torch.nn as nn
from torch.nn.parameter import Parameter
from torch.nn.modules.module import Module


class GraphConvolution(Module):
    def __init__(self, in_features, out_features, bias=True):
        super().__init__()
        self.weight = Parameter(torch.FloatTensor(in_features, out_features))
        if bias:
            self.bias = Parameter(torch.FloatTensor(out_features))
        else:
            self.register_parameter("bias", None)
        nn.init.xavier_normal_(self.weight.data, gain=0.02)
        if self.bias is not None:
            nn.init.constant_(self.bias.data, 0.0)

    def forward(self, input, adj):
        support = torch.mm(input, self.weight)
        if adj.layout == torch.strided:
            output = torch.mm(adj, support)
        else:
            sparse_adj = adj if adj.layout == torch.sparse_coo else adj.to_sparse()
            output = torch.sparse.mm(sparse_adj, support)
        if self.bias is not None:
            return output + self.bias
        return output
