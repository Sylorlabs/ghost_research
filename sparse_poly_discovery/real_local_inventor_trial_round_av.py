#!/usr/bin/env python3
"""Round AV: a narrow, real local-code tool-repair trial.

The candidate emits a Python analyzer into scratch, and the worker executes it
inside Bubblewrap against read-only *copies* of real repository Zig files.  The
evaluator's expected values never enter the sandbox.  This is deliberately a
single structural property, not an invention or general-intelligence claim.
"""
from __future__ import annotations

import csv
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TRAIN = ROOT / "core/src/adapters/invention_engine.zig"
HELDOUT = ROOT / "core/src/adapters/domain_agi_subsystem_synthesis.zig"

NAIVE = '''import sys
p = sys.argv[1]
print(sum(1 for line in open(p, encoding="utf-8") if "pub fn " in line))
'''
REPAIRED = '''import sys
p = sys.argv[1]
n = 0
for line in open(p, encoding="utf-8"):
    code = line.split("//", 1)[0]
    if "pub fn " in code:
        n += 1
print(n)
'''

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def evaluator_count(path: Path) -> int:
    # Evaluator-side oracle; this code/path is never mounted in the worker.
    return sum("pub fn " in line.split("//", 1)[0] for line in path.read_text().splitlines())

def run_worker(script: Path, corpus: Path, file_name: str) -> tuple[int, str]:
    cmd = [
        "bwrap", "--unshare-all", "--die-with-parent", "--new-session",
        "--clearenv", "--ro-bind", "/usr", "/usr", "--ro-bind", "/lib", "/lib",
        "--ro-bind", "/lib64", "/lib64", "--proc", "/proc", "--dev", "/dev",
        "--ro-bind", str(corpus), "/work/corpus", "--ro-bind", str(script),
        "/work/analyzer.py", "--tmpfs", "/tmp", "/usr/bin/python3",
        "/work/analyzer.py", f"/work/corpus/{file_name}",
    ]
    p = subprocess.run(cmd, text=True, capture_output=True, timeout=15, check=False)
    return p.returncode, p.stdout.strip()

def proposal_has_answer(source: str, expected: int) -> bool:
    # Audit for the trivial direct-number leak.  It does not prove source originality.
    return str(expected) in source

def main(out: Path) -> None:
    if not shutil.which("bwrap"):
        raise RuntimeError("Bubblewrap is required; refusing unsandboxed trial")
    for p in (TRAIN, HELDOUT):
        if not p.is_file():
            raise RuntimeError(f"missing real artifact: {p}")
    train_expected, held_expected = evaluator_count(TRAIN), evaluator_count(HELDOUT)
    rows: list[dict[str, str]] = []
    with tempfile.TemporaryDirectory(prefix="round-av-") as td:
        base = Path(td)
        corpus = base / "corpus"; corpus.mkdir()
        shutil.copyfile(TRAIN, corpus / "train.zig")
        shutil.copyfile(HELDOUT, corpus / "heldout.zig")
        os.chmod(corpus / "train.zig", 0o444); os.chmod(corpus / "heldout.zig", 0o444)

        # Candidate's first hypothesis/tool: count raw token appearances.
        attempts = [("candidate_naive", "raw_token_count", NAIVE, "train.zig", train_expected),
                    ("candidate_repaired", "comments_are_false_positives", REPAIRED, "train.zig", train_expected),
                    ("candidate_final", "sealed_transfer", REPAIRED, "heldout.zig", held_expected),
                    # Strong equal-capability baseline: not merely a weak naive rule.
                    ("fixed_comment_scanner", "fixed_baseline", REPAIRED, "heldout.zig", held_expected),
                    ("fixed_naive", "weak_baseline", NAIVE, "heldout.zig", held_expected)]
        for ordinal, (policy, hypothesis, source, target, expected) in enumerate(attempts, 1):
            script = base / f"{ordinal}.py"; script.write_text(source); os.chmod(script, 0o444)
            rc, raw = run_worker(script, corpus, target)
            correct = rc == 0 and raw.isdigit() and int(raw) == expected
            rows.append({
                "ordinal": str(ordinal), "policy": policy, "hypothesis": hypothesis,
                "artifact": target, "artifact_sha256": sha((corpus / target).read_bytes()),
                "source_sha256": sha(source.encode()), "worker_exit": str(rc),
                "candidate_output": raw, "expected_visible_to_worker": "false",
                "answer_literal_in_source": str(proposal_has_answer(source, expected)).lower(),
                "correct": str(correct).lower(),
                "receipt": sha(f"{policy}|{target}|{raw}|{rc}".encode()),
            })
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]), lineterminator="\n"); w.writeheader(); w.writerows(rows)
    # Real operational result, but no learned-superiority result: repaired ties fixed scanner.
    if rows[0]["correct"] != "false" or rows[1]["correct"] != "true" or rows[2]["correct"] != "true":
        raise RuntimeError("candidate repair protocol did not behave as precommitted")
    if rows[3]["correct"] != "true":
        raise RuntimeError("strong fixed baseline unexpectedly failed")
    print("round_av selftest PASS real_files=true sandboxed_worker=true repair=true transfer=true strong_fixed_tie=true verdict=OPERATES_BUT_NO_LEARNED_ADVANTAGE")

if __name__ == "__main__":
    main(Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "results/real_local_inventor_trial_round_av.csv")
