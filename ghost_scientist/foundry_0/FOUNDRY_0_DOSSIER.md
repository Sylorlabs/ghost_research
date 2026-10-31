# Foundry-0 novelty and falsification dossier

**Audit date:** 2026-07-30  
**Decision:** `FOUNDRY_0_GO_NARROWED`  
**Scope:** literature and local-artifact audit, not a claim of exhaustive
global novelty

## Executive verdict

Building a system that learns reusable program abstractions would not, by
itself, be novel. DreamCoder, Stitch, LILO, and ReGAL already learn reusable
libraries [S01–S04]. Automatically inferring rewrite rules is established by
Ruler and Enumo [S05–S06]. TENSAT, Ansor, MetaSchedule, and MCTS-guided
e-graphs already optimize tensor programs [S07–S10]. MISAAL automatically
generates semantics-driven compiler rewrites for real architectures [S11].
Most importantly, EggMind already synthesizes reusable equality-saturation
strategies, uses held-out cases, reports offline synthesis expense, and
evaluates an XLA-based tensor compiler [S12].

The original broad Foundry pitch therefore fails the novelty audit.

AlphaEvolve further prevents “evaluator-guided code evolution” from serving
as a novelty claim by itself [S14]. Work on prospective compression also
shows that selecting abstractions for uncertain future demand is already a
named library-learning problem, although that study concerns human behavior
rather than compilers [S15]. Babble already combines e-graphs,
anti-unification, and library learning modulo a supplied theory [S16].
ISAMORE is an even closer collision: it is an LLM-free end-to-end system that
discovers semantically reusable custom hardware instructions from real
applications and reports reuse, exploration cost, area, and speedup [S17].
Foundry therefore cannot claim the first LLM-free reusable-tool discovery
system or the first semantics-aware reusable instruction discovery system.

A narrower research gap survives. None of the audited systems establishes all
of the following in one experiment:

1. an LLM-free candidate grows executable typed tensor abstractions rather
   than selecting supplied strategy labels;
2. every successful and failed discovery, verification, compilation, and
   selection expense is charged;
3. reuse is proven behaviorally by exact tool identities and a causal removal
   intervention;
4. the comparison gives every baseline the same total research budget,
   including offline learning;
5. tools are frozen before independently sourced held-out artifacts are
   selected;
6. the primary outcome is measured compiler and executable behavior across
   heterogeneous workload families; and
7. a separate implementation reconstructs the verdict from raw receipts.

The 2026 EACL compute-matching critique makes items 2–4 necessary, not
decorative [S13]. EggMind makes a weak fixed/e-graph comparison inadequate:
it is now a required baseline [S12].

## Audit method

The audit searched primary paper and proceedings records for combinations of:

- program synthesis with library or abstraction learning;
- automatic rewrite-rule and equality-theory inference;
- reusable equality-saturation strategy synthesis;
- tensor graph superoptimization and schedule search;
- semantics-driven compiler optimization;
- compute-matched tool or library-learning evaluation;
- behavioral evidence of direct tool reuse; and
- prospective or online abstraction learning.

Sources were included when they collided with at least one part of the v6
claim or supplied a necessary control. Secondary summaries were used only to
locate primary sources and do not appear in the source ledger. The audit did
not perform citation-network saturation, contact authors, reproduce external
systems, or search subscription databases exhaustively. Those limits are why
the verdict is a bounded positioning decision rather than proof of novelty.

### Closest collisions

- **EggMind:** reusable EqSat strategy synthesis is already demonstrated.
  Its vectorization evaluation uses evolution and held-out cases; it reports
  offline synthesis time, model calls, tokens, and price separately; and it
  reports an XLA-based evaluation. Foundry therefore cannot claim novelty for
  reusable strategy artifacts, held-out EqSat strategy testing, offline cost
  reporting, or XLA application [S12].
- **Babble/ISAMORE:** e-graph anti-unification already learns abstractions
  modulo an equational theory, and ISAMORE already turns that mechanism into
  reusable custom instructions for real programs without an LLM. Foundry's
  remaining distinction is not the induction algorithm. It is the prospective
  causal and total-cost evaluation of executable typed software tools across
  heterogeneous post-freeze compiler workloads [S16–S17].
- **MISAAL:** offline automatic rewrite generation plus real retargetable
  compiler evaluation already exists. Foundry cannot claim that moving
  synthesis offline or generating compiler rewrites from supplied semantics
  is new [S11].
- **DreamCoder/Stitch/LILO/ReGAL:** useful abstraction discovery and later
  deployment are established. Foundry's distinction must come from the typed
  compiler outcome and evaluation protocol, not the existence of a growing
  library [S01–S04].
- **Compute-and-behavior audit:** equal total compute and direct behavioral
  analysis are already argued as required evaluation standards. Applying
  those standards is necessary rigor, not itself a novel algorithm [S13].

## Definitions that prevent claim inflation

### Primitive

A primitive is a semantic operation implemented below the candidate's
searchable language. If the evaluator supplies `add`, `mul`, tensor load,
reduction, or a compiler backend, those are supplied primitives.

### Derived tool

A derived tool is a typed, parameterized program composed from the frozen
substrate and promoted into a persistent library. It may alter practical
reachability and search depth. It does not escape the substrate's semantic
closure.

### Tool invention

Foundry may use “tool construction” or “derived-tool induction.” It must not
use “autonomous primitive invention” unless it constructs new semantics that
are unavailable through substrate composition and those semantics receive an
independent implementation. No such mechanism is proposed here.

### Newly reachable

“Newly reachable” means found within a frozen resource bound by the system but
not by a named control under the same bound. It does not mean mathematically
inexpressible unless an unbounded closure or fixpoint proof exists [L04–L06].

### Reuse

Direct reuse requires a held-out execution receipt naming the exact frozen
tool digest. Similar code, a helpful example in context, or improved aggregate
accuracy is not evidence of reuse. The EACL audit shows why behavioral
evidence is mandatory [S13].

### Net-positive

A library is net-positive only if its complete charged cost is lower than the
strongest compute-matched alternative at a predeclared point on an
externally justified workload trace. Merely reporting that an offline cost
“can be amortized” is insufficient.

## Prior-art collision matrix

Legend: **Y** directly demonstrated; **P** partial or adjacent; **N** absent
from the audited claim; **?** not established from the audited primary
source. “Heterogeneous transfer” specifically requires reuse of the same
learned artifact across distinct workload families; transferring a method by
retraining it separately does not qualify.

| Work | Grows abstractions or rules | Real compiler execution | Held-out reuse | Total compute matched | Behavioral causal reuse | Post-freeze selection | Heterogeneous transfer |
|---|---:|---:|---:|---:|---:|---:|---:|
| DreamCoder [S01] | Y | N | Y | N | P | N | N |
| Stitch [S02] | Y | N | P | P | P | N | N |
| LILO [S03] | Y | N | Y | N | P | N | N |
| ReGAL [S04] | Y | N | Y | N | P | N | N |
| Ruler [S05] | Y | P | N | P | N | N | N |
| Enumo [S06] | Y | P | N | P | N | N | N |
| TENSAT [S07] | N | Y | N | P | N | N | N |
| Ansor [S08] | N | Y | N | P | N | N | N |
| MetaSchedule [S09] | N | Y | N | P | N | N | P |
| MCTS tensor e-graphs [S10] | N | Y | N | P | N | N | N |
| MISAAL [S11] | Y | Y | P | P | P | N | Y |
| EggMind [S12] | Y | P | Y | P | P | N | N |
| Babble [S16] | Y | N | P | P | P | N | N |
| ISAMORE [S17] | Y | Y | P | P | P | N | N |
| Compute/behavior audit [S13] | N | N | audit | Y | Y | N | N |
| Ghost BA [L03] | Y | N | Y | P | Y | Y | N |
| Ghost v5.1 [L01–L02] | N | Y | Y | P | P | Y | Y |
| Proposed v6 | Y | Y | Y | Y | Y | Y | Y |

“Proposed v6” is a specification, not a result. Every cell must remain
unclaimed until its corresponding gate passes.

## What is already known locally

The local work rules out several easy stories:

- Round BA already machine-generated a locally new rewrite grammar and
  prospectively reused it. It explicitly identifies itself as a Ruler-family
  method and does not claim new mathematics [L03].
- The inner forge discovered useful monomials and then saturated at its
  substrate family [L05].
- The execution-only atom forge promoted relatively irreducible compositions
  but did not create primitives outside its opcode substrate [L06].
- Certified menu minting already raised synthetic solve coverage by promoting
  VM programs, while correctly describing them as within-VM compositions
  [L07].
- A persistent promote-and-reuse loop already exists on bounded scripted
  tasks [L08].
- v5.1 already supplies the prospective real-compiler protocol, numerical
  validation, reuse accounting, controls, containment, and independent
  recomputation. Its remaining boundary is supplied primitive semantics and
  rewrite theory [L01–L02].

Consequently, v6 cannot earn novelty by repeating synthetic library promotion,
machine-generated algebraic rules, persistent storage, or a frozen held-out
trial separately. Its contribution must be the causal total-cost connection
between autonomous typed abstraction growth and real heterogeneous compiler
outcomes.

## Surviving research question

> Under a frozen total research budget, can an LLM-free typed program
> synthesizer create and retain derived tensor tools that are directly reused
> on post-freeze real artifacts, and does that reuse produce a statistically
> supported net reduction in end-to-end discovery, verification, compilation,
> and execution cost versus the strongest fixed, replay, library-learning,
> rule-synthesis, strategy-synthesis, and per-instance-search controls?

This asks an unknown empirical question. A negative outcome is both possible
and valuable:

- abstraction discovery may cost more than it repays;
- tools may only help the family that created them;
- compute-matched per-instance search may erase the gain;
- an EggMind-style strategy may dominate;
- apparent reuse may disappear under the direct-use audit; or
- generated abstractions may merely duplicate compiler-native fusion.

## Primary hypothesis and estimand

Let a method process a chronological workload stream of length `N`.

`TotalCost_m(N)` includes:

- candidate-generation CPU time;
- all rejected and accepted tool verification;
- model inference, if an optional non-primary arm uses a model;
- compiler construction and compilation;
- selector/search time;
- executed workload time at externally sourced invocation counts; and
- failed/time-out attempts.

Peak memory and correctness are hard constraints, not exchangeable score
credits. CPU process time, wall time, compiler time, executed latency, model
tokens, and monetary API cost remain separately reported even when a frozen
primary scalar is computed.

The primary estimand is the paired relative total-cost difference against the
best baseline:

`Delta(N) = 1 - TotalCost_foundry(N) / TotalCost_best_control(N)`.

The primary hypothesis requires:

- a positive lower 95% paired bootstrap confidence bound for `Delta(N*)`;
- at least a 5% point improvement at the predeclared `N*`; and
- no correctness, provenance, containment, or memory failure.

`N*` may not be invented to make the result pass. It must come from an
independently sourced workload invocation trace. Without such a trace, the
experiment may report a break-even curve but cannot PASS the net-positive
gate.

## Required controls

The experiment is invalid without all critical controls:

1. **Stock compiler:** unchanged framework/compiler.
2. **v5.1 fixed conditional constructor:** strongest current local system.
3. **No-library rediscovery:** same candidate machinery and total budget, but
   no promoted tool may persist across artifacts.
4. **Replay:** nearest exact/structural prior result with no new tool creation.
5. **Stitch-style typed MDL learner:** abstraction discovery optimized for
   corpus compression [S02].
6. **Babble/ISAMORE-style anti-unification:** typed e-graph
   anti-unification producing reusable instruction/tool candidates, with
   hardware-specific scoring replaced only where required by the frozen
   software-compiler target [S16–S17].
7. **Ruler/Enumo-style rule inference:** semantics-derived rules with a fixed
   schedule [S05–S06].
8. **EggMind-style strategy synthesis:** reusable strategy artifact over the
   same rewrite vocabulary and cost model [S12].
9. **Compute-matched per-instance search:** spends the Foundry offline plus
   online budget directly on held-out artifacts and retains no library.
10. **Exhaustive bounded oracle:** only on a declared micro-corpus where
   completeness is feasible.
11. **Tool-removal intervention:** rerun the frozen selector with each selected
    invented tool unavailable; do not retrain.
12. **Native-compiler deduplication:** reject any “invented” tool that lowers
    to an already available compiler primitive or byte-identical compiler IR
    without changing search cost.

Controls 5–8 must use upstream artifacts when feasible. A local approximation
must be labeled `ADAPTED`, pass conformance fixtures derived from the source
paper, and cannot be called the upstream system.

## Candidate boundary

The primary candidate is LLM-free. It may use enumeration, typed
anti-unification, semantic equivalence classes, e-graphs, learned non-LLM cost
models, and verifier labels. This choice is not a claim that LLMs are
irrelevant; it isolates whether the tool economy itself works without hiding
extra test-time compute in a language model.

An optional LLM arm may be reported separately. It cannot rescue a failed
primary result and must charge model requests, tokens, latency, and price.

The candidate receives:

- the frozen typed low-level substrate;
- public calibration artifacts;
- type, shape, dtype, layout, alias, and numerical contracts;
- compiler measurements; and
- the resource budget.

It does not receive:

- artifact family labels;
- handcrafted size thresholds;
- named strategy choices;
- held-out artifacts or their digests;
- evaluator-private provenance;
- control outcomes;
- native-tool equivalence labels; or
- the pass thresholds during candidate execution.

## Corpus boundary

The primary held-out must be independently sourced, not solely
evaluator-authored motifs. Before freeze, the protocol fixes:

- allowed upstream projects and licenses;
- exact revisions or release archive hashes;
- graph-extraction code;
- exclusion rules;
- shape/input derivation procedure;
- workload trace source;
- stratification and sample count; and
- a commitment procedure for a post-freeze random seed.

After freeze, the seed selects artifacts and shapes. Candidate-visible inputs
contain only the typed problem contract. The evaluator retains provenance and
family audit data.

At least four non-transformer workload families are required. Attention may
appear only as one control family and may not exceed 20% of the corpus.

## Go/no-go decision

### GO, but only for the narrowed experiment

Proceed to a v6 development pilot only after these prerequisites exist:

- `P1`: upstream or conformance-tested implementations for the critical
  Stitch-, Babble/ISAMORE-, Ruler/Enumo-, and EggMind-style controls;
- `P2`: independently sourced graph corpus and invocation trace;
- `P3`: resource meter that charges all child processes, failures, compiler
  work, and optional model calls;
- `P4`: typed tool schema with independent parser, interpreter, and verifier;
- `P5`: native-compiler deduplication audit; and
- `P6`: freeze and post-freeze sampling runner inherited from v5.1 without
  weakened gates.

If any prerequisite is replaced with an unvalidated label or proxy, the
prospective trial is `INVALID`, not FAIL or PASS.

### Stop conditions

Stop v6 before a prospective trial if:

- no candidate tool survives native-compiler deduplication;
- development gains disappear under total compute matching;
- no tool transfers across evaluator-audited families;
- the EggMind-style or no-library control dominates;
- the Babble/ISAMORE-style control dominates;
- the workload trace cannot justify a break-even point; or
- tool verification cannot be made independent of candidate code.

These are successful scientific outcomes for Foundry-0's falsification
purpose. They prevent construction work from being mistaken for discovery.

## Allowed claim after a future PASS

> On a frozen, provenance-bound CPU workload stream, an LLM-free typed
> synthesizer induced executable derived tensor tools whose direct reuse
> produced a net total-cost advantage over compute-matched fixed, replay,
> library-learning, rule-synthesis, strategy-synthesis, and per-instance
> controls.

## Permanently disallowed conclusions from this protocol

- autonomous primitive or semantic invention;
- escape from a fixed computational substrate;
- new-to-human mathematics or algorithms;
- general autonomous science;
- architecture superiority;
- GPU or production readiness;
- universal cross-domain transfer; or
- proof that no prior publication contains a related combination.

## Audit limitations

The search covered the primary sources in `SOURCE_LEDGER.tsv` through
2026-07-30. It is a strong positioning audit, not a systematic review with
database-complete recall. EggMind is a recent preprint and must be rechecked
for revisions before v6 freeze. ISAMORE is a 2026 conference paper whose
reproduction and adaptation details must also be rechecked against its
released implementation. Source code availability, licenses, and reproduction
status for external controls remain implementation prerequisites, not
completed facts.
