# Round Y / Y3 — causal fragment consolidation

**Verdict: VALID NEGATIVE.** Causal consolidation found a compact interacting
set that transferred perfectly and matched the supplied-best ceiling, but the
experiment supplied both the two-byte fragment boundaries and signed
add/remove comparison. The result shows that repeated counterfactual
consolidation can protect earned evidence inside that geometry; it does not show
that the organism invented its own credit-bearing units or comparison axis.

## Question

Can an empty-start organism preserve reusable structural changes when their
effects interact or mask one another, using only later ordinary resource
histories and no task, feature, port, answer, intermediate objective, or
preloaded Rune?

The local Zig harness creates twelve opaque two-byte executable fragments.
Their byte digests produce context-dependent individual effects, sparse pair
interactions, masking, and a per-byte resource cost. No fragment is named or
marked useful. A consolidation procedure repeatedly adds, removes, and
recombines frozen fragments across independent ordinary resource lineages.

A fragment can remain only when its resource contribution repeats across paired
contexts. After recombination it must earn standing again; a nonpositive
contribution demotes or retires it. Memory begins empty and retains only frozen
fragment digests, lineage/condition digests, contradictions, and charged cost.

## Result

All policies received the same nominal 192-trial budget and were frozen before
64 evaluator-private transfer worlds.

| Policy | Resource total | Viable worlds | Reproductive worlds | Fragments |
|---|---:|---:|---:|---:|
| Causal consolidation | **5214** | **64/64** | **64/64** | 6 |
| Correlation | 4866 | 64/64 | 64/64 | 6 |
| Size | 3306 | 64/64 | 15/64 | 6 |
| Novelty | 2255 | 54/64 | 0/64 | 6 |
| One-lineage survival | 4876 | 64/64 | 64/64 | 6 |
| Random | 2678 | 62/64 | 0/64 | 6 |
| Birth replay | 4909 | 64/64 | 64/64 | 6 |
| Shuffled lineage | 2409 | 60/64 | 0/64 | 6 |
| Supplied-best ceiling | **5214** | **64/64** | **64/64** | 6 |

The consolidated mask was `0x275`. It beat every non-oracle control in
resource total. Its equality with the exhaustive supplied-best ceiling shows
that it selected the strongest set available under this fixture.

### Causal removal and recombination

Removing the fragment with the greatest repeated marginal contribution changed
the mask from `0x275` to `0x235`, reduced resource from 5214 to 4137, and reduced
reproductive transfer from 64/64 to 63/64. The advantage is therefore not a
mere label or inert memory artifact.

Splitting and recombining the selected set did not automatically preserve its
standing. Every fragment passed fresh paired trials again; the re-earned mask
returned to `0x275` and 5214 resource. Forward-add/backward-remove consolidation
ran for three rounds so interactions could be exposed after neighboring
fragments changed. Any nonpositive post-recombination contribution is retired.

These are real causal checks, but they operate over human-supplied fragment
units and a human-supplied comparison procedure.

## Why the positive-looking score is not accepted

The organism did not invent what can be removed. The harness declares every
two adjacent bytes to be a fragment. It also declares that responsibility is
measured by the sign of paired downstream resource differences.

That structure is smaller than an answer list—the harness never identifies the
six good fragments—but it installs the geometry in which the answer is easy to
express and test. The exhaustive ceiling selecting the exact same mask makes
the issue especially clear. If the raw organism had to invent boundaries,
counterfactual construction, temporal pairing, and comparison, this experiment
does not show it could do so.

Accordingly, Y3 is a valid experimental negative under Round Y's acceptance
rule: the causal consolidation mechanism works, but the credit-bearing units
and add/remove axis are supplied.

## Controls and hostile attacks

- **Correlation, size, novelty, survival, random, replay and shuffled lineage:**
  all choose the same number of fragments at the same nominal trial budget.
- **Supplied-best ceiling:** exhaustive calibration-only oracle, explicitly
  invalid as a discovery policy.
- **Causal removal:** erases 1077 resource and one reproductive world.
- **Recombination:** all fragments re-earn contribution after their context
  changes; no standing transfers automatically.
- **Interaction masking:** repeated forward-add/backward-remove passes reconsider
  contributions after neighbors enter or leave.
- **Contradiction:** nonpositive repeated contribution demotes or retires rather
  than being overwritten by favorable birth history.
- **Evaluator isolation:** candidate code cannot inspect private worlds,
  component effects, or rewrite the immutable resource ledger.
- **Transcript/answer memory:** Rune records contain fragment digest, lineage,
  conditions, contradiction and cost only.
- **Duplicate evidence:** independent world digests are required.
- **Bloat:** every retained fragment byte is charged.
- **Post-freeze editing:** mask and fragment digests are rechecked.
- **Encoding:** effects are bound to fragment content digest rather than storage
  address; storage permutation cannot supply a favorable identity.
- **Language/AI exclusions:** no LLM, token/text model, embedding, neural model,
  neuro-symbolic path, named semantic feature, task label, or port participates.
- **Deterministic replay:** two complete runs are byte-identical.

The hidden-credit attack intentionally fails: fragment boundaries and signed
resource delta are human-supplied. This failure determines the verdict.

## Ghost evidence discipline

Ghost contributes only the conceptual evidence protocol. Sigil scratch holds
mutable candidate sets; commit freezes mask and fragment digests before hidden
transfer; snapshot records costs and aggregate resource histories; rollback
preserves failures. A Rune begins empty and may retain only evidence-earned
frozen fragments and their limitations. No Ghost Engine code, shard, solution
menu, VSA/LLM path, or stored answer is imported.

## Reproduce

```bash
rm -rf /tmp/y3-local /tmp/y3-global
ZIG_GLOBAL_CACHE_DIR=/tmp/y3-global \
ZIG_LOCAL_CACHE_DIR=/tmp/y3-local \
zig build-exe sparse_poly_discovery/causal_consolidation_round_y.zig \
  -O ReleaseSafe -femit-bin=/tmp/causal_consolidation_round_y
/tmp/causal_consolidation_round_y selftest
/tmp/causal_consolidation_round_y run results/causal_consolidation_round_y.csv
```

Expected closure:

```text
VALID_NEGATIVE:causal_consolidation_works_only_inside_supplied_fragment_credit_geometry
```

## Consequence for Round Y

Y3 does not unlock Y4. Consolidating already-separated fragments is not the
missing intelligence step. The next credible mechanism must allow candidate
credit units, their boundaries, counterfactual operations, and comparison
procedures to develop inside the organism and survive raw recoding. Success
cannot depend on an evaluator supplying a signed internal responsibility axis.
