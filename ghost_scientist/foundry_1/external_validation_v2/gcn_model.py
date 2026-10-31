"""Model-only snapshot from pytorch/examples gcn/main.py."""

import torch
from torch import nn
import torch.nn.functional as F


class GraphConv(nn.Module):
    def __init__(self, input_dim, output_dim, use_bias=False):
        super().__init__()
        self.kernel = nn.Parameter(torch.Tensor(input_dim, output_dim))
        nn.init.xavier_normal_(self.kernel)
        self.bias = None
        if use_bias:
            self.bias = nn.Parameter(torch.Tensor(output_dim))
            nn.init.zeros_(self.bias)

    def forward(self, input_tensor, adj_mat):
        support = torch.mm(input_tensor, self.kernel)
        output = torch.spmm(adj_mat, support)
        if self.bias is not None:
            output = output + self.bias
        return output


class GCN(nn.Module):
    def __init__(
        self, input_dim, hidden_dim, output_dim, use_bias=True, dropout_p=0.1
    ):
        super().__init__()
        self.gc1 = GraphConv(input_dim, hidden_dim, use_bias=use_bias)
        self.gc2 = GraphConv(hidden_dim, output_dim, use_bias=use_bias)
        self.dropout = nn.Dropout(dropout_p)

    def forward(self, input_tensor, adj_mat):
        x = self.gc1(input_tensor, adj_mat)
        x = F.relu(x)
        x = self.dropout(x)
        x = self.gc2(x, adj_mat)
        return F.log_softmax(x, dim=1)
