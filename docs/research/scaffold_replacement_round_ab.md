# Round AB / AB3 — bootstrap scaffold replacement
**Verdict: VALID NEGATIVE.** A fully internal, fail-closed replacement pipeline
was demonstrated on a uniform raw tape, but it does **not** establish
architecture-owning self-improvement. The search still inherits human-chosen
raw-byte intervention boundaries and a human-written proposal generator, and
its selected successor changes under value recoding.

## Question

Can an organism treat every human-origin organism-owned instrument as
`UNVERIFIED_SCAFFOLD`, detect measured failure from opaque causal evidence,
construct its own alternative without an external builder, freeze old/new
states at equal cost, evaluate on fresh private contexts, ablate the replacement,
and autonomously commit or roll back?

## Bounded instrument

The organism is one uniform 64-byte tape. There is no component table, room
name, request packet, implementation menu, semantic feature, task label, or
privileged human-origin bit. For each raw location it constructs 16 candidate
bytes only from organism-owned tape bytes, mutable nonce state, and opaque
mixing. Charged calibration interventions select a whole-tape successor. Old
and candidate tapes freeze before 18 disjoint hidden contexts per cohort.

The evaluator privately relocates all 64 positions and XOR-recodes their raw
values for the recoding attack. The organism sees neither the logical mapping
nor the private target bytes. Unfavorable candidates roll back; successful ones
commit. Removing the replacement restores the old tape exactly.

This is a deliberately tiny microscope. Its evaluator physics are not an
intelligence task and the oracle exists only as a private reachable ceiling.

## Results

Across 20 independently seeded cohorts:

| Policy | Charged trials | Old resource | Committed resource | Commit / rollback |
|---|---:|---:|---:|---:|
| evidence-built replacement | 204,800 | 91,736 | **148,616** | 20 / 0 |
| same procedure after relocation/value recoding | 204,800 | 91,736 | 148,886 | 20 / 0 |
| random replacement | 204,800 | 91,736 | 93,194 | 10 / 10 |
| frequency-only | 204,800 | 91,736 | 94,670 | 12 / 8 |
| address-only partial replacement | 204,800 | 91,736 | 99,116 | 20 / 0 |
| request-free unguided synthesis | 204,800 | 91,736 | 93,518 | 7 / 13 |
| fixed / human-origin / no replacement | 0 | 91,736 | 91,736 | 0 / 20 |
| shuffled evidence | 204,800 | 91,736 | 148,220 | 20 / 0 |
| false evidence | 204,800 | 91,736 | 91,736 | 0 / 20 |
| private oracle ceiling | 0 | 91,736 | 184,346 | 20 / 0 |

The internal pipeline therefore does real work: it beats ordinary controls,
false evidence causes complete rollback, human origin receives no privilege,
and causal ablation returns **exactly 91,736**, the old resource total.

## Why this is still negative

Two attacks fail the full claim.

1. **Humans still chose the atom.** The organism was not handed rooms, but the
   VM still presented separately mutable bytes and a byte-replacement operation.
   That is a finer hidden decomposition, not decomposition-free construction.
2. **Humans still wrote the variation physics.** The proposal generator is
   answer-free and uses only organism-owned state, but the organism did not
   invent that generator. It cannot yet replace the procedure that proposed the
   replacement.

The relocation/value-recoding run remains numerically strong, but it produces a
different successor and a different resource total (148,886 rather than
148,616). That is evidence the forge is coupled to representational material,
not an invariant reconstruction of function. Shuffled evidence also loses only
396 resource units, so the evidence-to-location binding is weaker than the raw
headline suggests.

Accordingly, the bounded positive is **replacement pipeline functionality**,
not autonomous self-improvement. AB3 does not release AB4.

## Hostile controls

The ledger records attacks for hidden room/component tables, external builder
or request channels, evaluator target leakage, uncharged trials, favorable
birth, post-test edits, bloat, forged provenance, freeze violations,
human-origin privilege, deterministic replay, and LLM/text/embedding/neural or
neuro-symbolic dependence. These pass. The raw-byte/proposal-scaffold and
recoding-invariance attacks fail and dominate the verdict.

## Reproduce

```bash
mkdir -p /tmp/zig-cache-ab3 /tmp/zig-global-ab3
zig build-exe sparse_poly_discovery/scaffold_replacement_round_ab.zig \
  -femit-bin=/tmp/scaffold_replacement_round_ab \
  --cache-dir /tmp/zig-cache-ab3 --global-cache-dir /tmp/zig-global-ab3
/tmp/scaffold_replacement_round_ab selftest
/tmp/scaffold_replacement_round_ab run results/scaffold_replacement_round_ab.csv
```

Expected self-test:

```text
round_ab_ab3 selftest PASS verdict=VALID_NEGATIVE deterministic=true replacement_gain=true recode=false
```

Artifacts:

- `sparse_poly_discovery/scaffold_replacement_round_ab.zig`
- `results/scaffold_replacement_round_ab.csv`
- `docs/research/scaffold_replacement_round_ab.md`
