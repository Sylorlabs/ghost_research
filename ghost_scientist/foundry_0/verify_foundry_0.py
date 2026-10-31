#!/usr/bin/env python3
"""Structural audit for the Foundry-0 research dossier."""

from __future__ import annotations

import csv
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FOUNDRY_0_VERIFY_FAIL: {message}")


def load_sources() -> dict[str, dict[str, str]]:
    path = HERE / "SOURCE_LEDGER.tsv"
    with path.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    require(rows, "source ledger is empty")
    require(
        set(rows[0]) == {
            "id",
            "kind",
            "year",
            "title",
            "venue",
            "url",
            "relevance",
            "non_coverage",
        },
        "unexpected source ledger schema",
    )
    sources: dict[str, dict[str, str]] = {}
    for row in rows:
        source_id = row["id"]
        require(re.fullmatch(r"[SL]\d{2}", source_id) is not None, f"bad source id {source_id}")
        require(source_id not in sources, f"duplicate source id {source_id}")
        require(row["relevance"].strip() != "", f"{source_id} lacks relevance")
        require(row["non_coverage"].strip() != "", f"{source_id} lacks non-coverage")
        if row["kind"] == "external_primary":
            require(row["url"].startswith("https://"), f"{source_id} lacks HTTPS primary URL")
        elif row["kind"] == "local_evidence":
            require((ROOT / row["url"]).is_file(), f"{source_id} local path missing: {row['url']}")
        else:
            require(False, f"{source_id} has unknown kind {row['kind']}")
        sources[source_id] = row
    return sources


def expand_citation(expression: str) -> set[str]:
    found: set[str] = set()
    for item in expression.split(","):
        item = item.strip()
        match = re.fullmatch(r"([SL])(\d{2})(?:[–-]([SL])?(\d{2}))?", item)
        require(match is not None, f"bad citation expression {item!r}")
        prefix, start_text, end_prefix, end_text = match.groups()
        if end_text is None:
            found.add(f"{prefix}{start_text}")
            continue
        require(end_prefix in (None, prefix), f"mixed citation range {item!r}")
        start = int(start_text)
        end = int(end_text)
        require(start <= end, f"descending citation range {item!r}")
        found.update(f"{prefix}{number:02d}" for number in range(start, end + 1))
    return found


def audit_citations(sources: dict[str, dict[str, str]]) -> None:
    dossier = (HERE / "FOUNDRY_0_DOSSIER.md").read_text(encoding="utf-8")
    cited: set[str] = set()
    for expression in re.findall(r"\[([SL]\d{2}(?:(?:[–-][SL]?\d{2})|(?:,\s*[SL]\d{2}))*)\]", dossier):
        cited.update(expand_citation(expression))
    missing = sorted(cited - sources.keys())
    require(not missing, f"undefined citations: {missing}")
    external = {source_id for source_id in cited if source_id.startswith("S")}
    local = {source_id for source_id in cited if source_id.startswith("L")}
    require(len(external) >= 12, f"only {len(external)} external primary sources cited")
    require(len(local) >= 8, f"only {len(local)} local evidence sources cited")


def audit_protocol() -> None:
    protocol = (HERE / "FALSIFICATION_PROTOCOL.md").read_text(encoding="utf-8")
    validity = re.findall(r"^\| (V\d{2}) \|", protocol, flags=re.MULTILINE)
    research = re.findall(r"^\| (R\d{2}) \|", protocol, flags=re.MULTILINE)
    arms = re.findall(r"^\| (A\d{1,2}) \|", protocol, flags=re.MULTILINE)
    require(validity == [f"V{i:02d}" for i in range(1, 13)], "validity gates are not V01..V12")
    require(research == [f"R{i:02d}" for i in range(1, 13)], "research gates are not R01..R12")
    require(arms == [f"A{i}" for i in range(11)], "arms are not A0..A10")
    for verdict in ("PASS", "FAIL", "INVALID", "NOT_RUN"):
        require(f"`FOUNDRY_V6_{verdict}`" in protocol, f"missing verdict {verdict}")


def audit_decision() -> None:
    decision = json.loads((HERE / "decision.json").read_text(encoding="utf-8"))
    require(decision["schema"] == "ghost-foundry-0-decision-v1", "bad decision schema")
    require(decision["verdict"] == "FOUNDRY_0_GO_NARROWED", "unexpected decision")
    require(decision["primary_candidate_llm_free"] is True, "primary candidate boundary changed")
    require(decision["prospective_trial_authorized"] is False, "trial prematurely authorized")
    require(len(decision["critical_controls"]) == 10, "critical control count changed")
    require(
        "babble-isamore-adaptation" in decision["critical_controls"],
        "closest anti-unification control is missing",
    )
    require(
        "first LLM-free derived-tool construction" in decision["broad_claims_rejected"],
        "ISAMORE claim collision is missing",
    )
    require(len(decision["prerequisites"]) == 6, "prerequisite count changed")


def main() -> None:
    for name in (
        "README.md",
        "FOUNDRY_0_DOSSIER.md",
        "FALSIFICATION_PROTOCOL.md",
        "SOURCE_LEDGER.tsv",
        "decision.json",
        "GOAL_CLOSURE.md",
    ):
        require((HERE / name).is_file(), f"missing required artifact {name}")
    sources = load_sources()
    audit_citations(sources)
    audit_protocol()
    audit_decision()
    print(
        "FOUNDRY_0_VERIFY_PASS "
        f"sources={len(sources)} external={sum(k.startswith('S') for k in sources)} "
        f"local={sum(k.startswith('L') for k in sources)} arms=11 "
        "validity_gates=12 research_gates=12"
    )


if __name__ == "__main__":
    main()
