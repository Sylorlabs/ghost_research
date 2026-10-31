#!/usr/bin/env python3
"""Independent output, metadata, and alias checks for framework mounts."""

from __future__ import annotations

import hashlib
import json
import math
from typing import Any

import torch


class IndependentRuntimeReject(ValueError):
    pass


def clone_tree(value: Any) -> Any:
    if isinstance(value, torch.Tensor):
        return value.detach().clone().requires_grad_(value.requires_grad)
    if isinstance(value, tuple):
        return tuple(clone_tree(item) for item in value)
    if isinstance(value, list):
        return [clone_tree(item) for item in value]
    if isinstance(value, dict):
        return {key: clone_tree(item) for key, item in value.items()}
    return value


def tensor_leaves(value: Any) -> list[torch.Tensor]:
    if isinstance(value, torch.Tensor):
        return [value]
    if isinstance(value, (tuple, list)):
        return [
            tensor
            for item in value
            for tensor in tensor_leaves(item)
        ]
    if isinstance(value, dict):
        return [
            tensor
            for key in sorted(value, key=str)
            for tensor in tensor_leaves(value[key])
        ]
    return []


def structure(value: Any) -> Any:
    if isinstance(value, torch.Tensor):
        return {
            "tensor": {
                "shape": list(value.shape),
                "dtype": str(value.dtype),
                "layout": str(value.layout),
                "stride": list(value.stride())
                if value.layout == torch.strided
                else None,
                "storage_offset": value.storage_offset()
                if value.layout == torch.strided
                else None,
            }
        }
    if isinstance(value, tuple):
        return {"tuple": [structure(item) for item in value]}
    if isinstance(value, list):
        return {"list": [structure(item) for item in value]}
    if isinstance(value, dict):
        return {
            "dict": [
                [str(key), structure(value[key])]
                for key in sorted(value, key=str)
            ]
        }
    if value is None or type(value) in {bool, int, float, str}:
        return {"literal": value}
    raise IndependentRuntimeReject(
        f"unsupported output type {type(value).__name__}"
    )


def alias_matrix(value: Any) -> list[list[bool]]:
    leaves = tensor_leaves(value)
    matrix = []
    for left in leaves:
        row = []
        for right in leaves:
            if left.layout != torch.strided or right.layout != torch.strided:
                row.append(left is right)
            else:
                row.append(
                    left.untyped_storage().data_ptr()
                    == right.untyped_storage().data_ptr()
                )
        matrix.append(row)
    return matrix


def digest_tree(value: Any) -> str:
    digest = hashlib.sha256()
    digest.update(
        json.dumps(
            structure(value), sort_keys=True, separators=(",", ":")
        ).encode()
    )
    for tensor in tensor_leaves(value):
        dense = tensor.detach().cpu()
        if dense.layout != torch.strided:
            dense = dense.to_dense()
        contiguous = dense.contiguous().reshape(-1)
        digest.update(contiguous.view(torch.uint8).numpy().tobytes())
    return digest.hexdigest()


def primary_compare(expected: Any, actual: Any) -> dict:
    if structure(expected) != structure(actual):
        raise IndependentRuntimeReject("output structure or metadata mismatch")
    expected_leaves = tensor_leaves(expected)
    actual_leaves = tensor_leaves(actual)
    maximum = 0.0
    for left, right in zip(expected_leaves, actual_leaves):
        if left.numel() == 0:
            continue
        if left.dtype.is_floating_point or left.dtype.is_complex:
            error = (left.detach() - right.detach()).abs().max().item()
            if not math.isfinite(float(error)):
                raise IndependentRuntimeReject("nonfinite output error")
            maximum = max(maximum, float(error))
        elif not torch.equal(left.detach(), right.detach()):
            raise IndependentRuntimeReject("exact output mismatch")
    aliases_equal = alias_matrix(expected) == alias_matrix(actual)
    if not aliases_equal:
        raise IndependentRuntimeReject("output alias relation mismatch")
    return {
        "max_abs_error": maximum,
        "alias_storage_checks_passed": aliases_equal,
        "expected_sha256": digest_tree(expected),
        "actual_sha256": digest_tree(actual),
    }


def independent_assert(expected: Any, actual: Any) -> None:
    try:
        torch.testing.assert_close(
            actual,
            expected,
            rtol=1.0e-6,
            atol=1.0e-6,
            equal_nan=False,
            check_device=True,
            check_dtype=True,
            check_layout=True,
            check_stride=True,
        )
    except Exception as exc:
        raise IndependentRuntimeReject(
            f"framework assertion failed: {type(exc).__name__}"
        ) from exc
