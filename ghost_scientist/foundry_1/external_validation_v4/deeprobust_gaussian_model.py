"""GGCL_F slice from DSE-MSU/DeepRobust."""

import torch
import torch.nn.functional as F
from torch.nn.parameter import Parameter
from torch.nn.modules.module import Module


class GGCL_F(Module):
    def __init__(self, in_features, out_features, dropout=0.0):
        super().__init__()
        self.dropout = dropout
        self.weight_miu = Parameter(torch.FloatTensor(in_features, out_features))
        self.weight_sigma = Parameter(torch.FloatTensor(in_features, out_features))
        torch.nn.init.xavier_uniform_(self.weight_miu)
        torch.nn.init.xavier_uniform_(self.weight_sigma)

    def forward(self, features, adj_norm1, adj_norm2, gamma=1):
        features = F.dropout(features, self.dropout, training=self.training)
        miu = F.elu(torch.mm(features, self.weight_miu))
        sigma = F.relu(torch.mm(features, self.weight_sigma))
        attenuation = torch.exp(-gamma * sigma)
        miu_out = adj_norm1 @ (miu * attenuation)
        sigma_out = adj_norm2 @ (sigma * attenuation * attenuation)
        return miu_out, sigma_out
