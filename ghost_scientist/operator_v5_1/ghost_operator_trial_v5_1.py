#!/usr/bin/env python3
"""Locked wrapper around the byte-identical frozen v5 integrated trial."""

from __future__ import annotations

import argparse
import pathlib
import sys


HERE = pathlib.Path(__file__).resolve().parent
V5 = HERE.parent / "operator_v5"
sys.path.insert(0, str(V5))
sys.path.insert(0, str(HERE))

from ghost_operator_freeze_v5_1 import verify as verify_v5_1  # noqa: E402
from ghost_operator_trial_v5 import run_trial  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=pathlib.Path)
    parser.add_argument("private_audit", type=pathlib.Path)
    parser.add_argument("output_root", type=pathlib.Path)
    parser.add_argument("--repetitions", type=int, default=11)
    args = parser.parse_args()
    freeze_v5_1 = HERE / "results/protocol_freeze_v5_1.txt"
    verify_v5_1(HERE, freeze_v5_1)
    run_trial(
        args.manifest.resolve(),
        args.private_audit.resolve(),
        HERE / "results/frozen_grammar_v5_1.json",
        HERE / "results/frozen_fixed_portfolio_v5_1.json",
        V5 / "results/protocol_freeze_v5.txt",
        args.output_root.resolve(),
        repetitions=args.repetitions,
    )


if __name__ == "__main__":
    main()

