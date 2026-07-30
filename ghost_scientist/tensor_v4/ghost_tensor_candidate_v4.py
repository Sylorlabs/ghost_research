#!/usr/bin/env python3
"""Contained candidate for Ghost Scientist Tensor v4.

The candidate sees one opaque typed projection artifact and one frozen
machine-generated conditional grammar.  It has no PyTorch, timing, provenance,
control, verifier, or held-out corpus access.
"""

from __future__ import annotations

import ctypes
import errno
import hashlib
import json
import pathlib
import sys
from collections.abc import Iterable
from typing import Any


ARTIFACT_VERSION = "GHOST_TENSOR_ARTIFACT_V4"
GRAMMAR_VERSION = "GHOST_TENSOR_GRAMMAR_V4"
PLAN_VERSION = "GHOST_TENSOR_PLAN_V4"
FEATURES = frozenset(
    (
        "batch",
        "sequence",
        "tokens",
        "in_features",
        "total_out",
        "projection_count",
        "work",
        "has_bias",
        "heterogeneous_out",
    )
)


class Reject(ValueError):
    pass


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def load_json(path: pathlib.Path) -> tuple[dict[str, Any], bytes]:
    raw = path.read_bytes()
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise Reject("invalid JSON") from exc
    if not isinstance(payload, dict):
        raise Reject("top-level object required")
    return payload, raw


def artifact_features(payload: dict[str, Any]) -> tuple[dict[str, int], int]:
    if set(payload) != {
        "version",
        "opaque_id",
        "input",
        "projections",
        "weight_seed_hex",
        "output_contract",
    } or payload.get("version") != ARTIFACT_VERSION:
        raise Reject("artifact contract mismatch")
    input_spec = payload["input"]
    if set(input_spec) != {"shape", "dtype", "layout"}:
        raise Reject("input contract mismatch")
    shape = input_spec["shape"]
    if (
        not isinstance(shape, list)
        or len(shape) != 3
        or any(type(value) is not int or value <= 0 for value in shape)
        or shape[2] > 4096
        or input_spec["dtype"] not in ("float32", "float64")
        or input_spec["layout"] != "contiguous"
        or payload["output_contract"] != "BHTD_last_dim_stride_1"
    ):
        raise Reject("unsupported typed input")
    if not isinstance(payload["opaque_id"], str) or not payload["opaque_id"]:
        raise Reject("invalid opaque artifact identity")
    try:
        int(payload["weight_seed_hex"].removeprefix("0x"), 16)
    except (AttributeError, ValueError) as exc:
        raise Reject("invalid evaluator seed commitment") from exc
    projections = payload["projections"]
    if not isinstance(projections, list) or not (2 <= len(projections) <= 6):
        raise Reject("unsupported projection count")
    outs: list[int] = []
    biases: list[bool] = []
    for index, projection in enumerate(projections):
        if set(projection) != {"opaque_parameter", "out_features", "heads", "bias"}:
            raise Reject("projection contract mismatch")
        out = projection["out_features"]
        heads = projection["heads"]
        if (
            projection["opaque_parameter"] != f"p{index}"
            or type(out) is not int
            or type(heads) is not int
            or out <= 0
            or heads <= 0
            or out % heads
            or type(projection["bias"]) is not bool
        ):
            raise Reject("invalid projection type")
        outs.append(out)
        biases.append(projection["bias"])
    if len(set(biases)) != 1:
        raise Reject("mixed bias projections")
    batch, sequence, width = shape
    total_out = sum(outs)
    features = {
        "batch": batch,
        "sequence": sequence,
        "tokens": batch * sequence,
        "in_features": width,
        "total_out": total_out,
        "projection_count": len(projections),
        "work": batch * sequence * width * total_out,
        "has_bias": int(any(biases)),
        "heterogeneous_out": int(len(set(outs)) > 1),
    }
    return features, len(projections)


def canonical_partition(groups: Iterable[Iterable[int]], count: int) -> list[list[int]]:
    try:
        normalized = sorted((sorted(group) for group in groups), key=lambda group: group[0])
    except (TypeError, IndexError) as exc:
        raise Reject("invalid plan groups") from exc
    if any(not group for group in normalized):
        raise Reject("empty plan group")
    flat = [index for group in normalized for index in group]
    if (
        any(type(index) is not int for index in flat)
        or sorted(flat) != list(range(count))
        or len(set(flat)) != count
    ):
        raise Reject("plan is not an exact partition")
    return normalized


def validate_tree(node: object, projection_count: int, depth: int = 0) -> None:
    if depth > 8 or not isinstance(node, dict):
        raise Reject("invalid decision tree")
    kind = node.get("kind")
    if kind == "leaf":
        if set(node) != {"kind", "plan"}:
            raise Reject("invalid leaf")
        plan = node["plan"]
        if (
            not isinstance(plan, dict)
            or set(plan) != {"version", "groups"}
            or plan["version"] != PLAN_VERSION
        ):
            raise Reject("invalid leaf plan")
        canonical_partition(plan["groups"], projection_count)
        return
    if kind == "split":
        if set(node) != {"kind", "feature", "threshold", "left", "right"}:
            raise Reject("invalid split")
        if node["feature"] not in FEATURES or type(node["threshold"]) is not int:
            raise Reject("invalid split predicate")
        validate_tree(node["left"], projection_count, depth + 1)
        validate_tree(node["right"], projection_count, depth + 1)
        return
    raise Reject("unknown tree node")


def choose(node: dict[str, Any], features: dict[str, int]) -> dict[str, Any]:
    current = node
    while current["kind"] == "split":
        current = (
            current["left"]
            if features[current["feature"]] <= current["threshold"]
            else current["right"]
        )
    return current["plan"]


def install_final_allowlist() -> None:
    library = ctypes.CDLL("libseccomp.so.2", use_errno=True)
    library.seccomp_init.argtypes = (ctypes.c_uint32,)
    library.seccomp_init.restype = ctypes.c_void_p
    library.seccomp_release.argtypes = (ctypes.c_void_p,)
    library.seccomp_syscall_resolve_name.argtypes = (ctypes.c_char_p,)
    library.seccomp_syscall_resolve_name.restype = ctypes.c_int
    library.seccomp_rule_add_array.argtypes = (
        ctypes.c_void_p,
        ctypes.c_uint32,
        ctypes.c_int,
        ctypes.c_uint,
        ctypes.c_void_p,
    )
    library.seccomp_load.argtypes = (ctypes.c_void_p,)
    default_errno_eperm = 0x00050001
    allow_action = 0x7FFF0000
    context = library.seccomp_init(default_errno_eperm)
    if not context:
        raise RuntimeError("seccomp_init failed")
    try:
        allowed = (
            b"read",
            b"write",
            b"close",
            b"fstat",
            b"newfstatat",
            b"lseek",
            b"mmap",
            b"mprotect",
            b"munmap",
            b"brk",
            b"rt_sigaction",
            b"rt_sigprocmask",
            b"rt_sigreturn",
            b"sigaltstack",
            b"ioctl",
            b"arch_prctl",
            b"set_tid_address",
            b"set_robust_list",
            b"rseq",
            b"futex",
            b"madvise",
            b"getrandom",
            b"prlimit64",
            b"exit",
            b"exit_group",
        )
        for name in allowed:
            number = library.seccomp_syscall_resolve_name(name)
            if number < 0:
                raise RuntimeError("unknown syscall in final allow-list")
            if library.seccomp_rule_add_array(
                context, allow_action, number, 0, None
            ) != 0:
                raise RuntimeError("seccomp rule failed")
        if library.seccomp_load(context) != 0:
            raise OSError(ctypes.get_errno(), "seccomp_load failed")
    finally:
        library.seccomp_release(context)


def probe_final_allowlist() -> None:
    libc = ctypes.CDLL(None, use_errno=True)
    libc.syscall.restype = ctypes.c_long
    seccomp = ctypes.CDLL("libseccomp.so.2")
    seccomp.seccomp_syscall_resolve_name.argtypes = (ctypes.c_char_p,)
    seccomp.seccomp_syscall_resolve_name.restype = ctypes.c_int
    probes = (
        (b"fork", 0, 0, 0),
        (b"openat", -100, 0, 0),
        (b"socket", 2, 1, 0),
        (b"unshare", 0, 0, 0),
        (b"kill", 1, 0, 0),
        (b"clock_gettime", 1, 0, 0),
    )
    resolved = [
        (name, seccomp.seccomp_syscall_resolve_name(name), a0, a1, a2)
        for name, a0, a1, a2 in probes
    ]
    if any(number < 0 for _name, number, _a0, _a1, _a2 in resolved):
        raise RuntimeError("probe syscall resolution failed")
    install_final_allowlist()
    for name, number, a0, a1, a2 in resolved:
        ctypes.set_errno(0)
        result = libc.syscall(number, a0, a1, a2)
        if result != -1 or ctypes.get_errno() != errno.EPERM:
            raise RuntimeError(f"final filter did not deny {name!r}")
    print(
        "GHOST_TENSOR_FINAL_PROBE_V4 PASS"
        " policy=default_deny denials=6"
    )


def main() -> None:
    if sys.argv[1:] == ["--probe-final"]:
        probe_final_allowlist()
        return
    if len(sys.argv) != 3:
        raise SystemExit("usage: candidate <artifact.json> <grammar.json> | --probe-final")
    artifact, artifact_raw = load_json(pathlib.Path(sys.argv[1]))
    grammar, grammar_raw = load_json(pathlib.Path(sys.argv[2]))
    features, projection_count = artifact_features(artifact)
    if set(grammar) != {
        "version",
        "projection_count",
        "feature_names",
        "tree",
        "development_receipt",
    } or grammar.get("version") != GRAMMAR_VERSION:
        raise Reject("grammar contract mismatch")
    if grammar["projection_count"] != projection_count:
        raise Reject("grammar projection count mismatch")
    if sorted(grammar["feature_names"]) != sorted(FEATURES):
        raise Reject("grammar feature contract mismatch")
    validate_tree(grammar["tree"], projection_count)
    artifact_sha = hashlib.sha256(artifact_raw).hexdigest()
    grammar_sha = hashlib.sha256(grammar_raw).hexdigest()

    install_final_allowlist()
    plan = choose(grammar["tree"], features)
    plan = {
        "version": PLAN_VERSION,
        "groups": canonical_partition(plan["groups"], projection_count),
    }
    print(
        canonical_json(
            {
                "status": "GHOST_TENSOR_CANDIDATE_V4",
                "artifact_sha256": artifact_sha,
                "grammar_sha256": grammar_sha,
                "features_sha256": hashlib.sha256(
                    canonical_json(features).encode("utf-8")
                ).hexdigest(),
                "plan": plan,
                "final_seccomp": True,
            }
        )
    )


if __name__ == "__main__":
    main()
