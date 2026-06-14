const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const exe = b.addExecutable(.{
        .name = "world_injection",
        .root_source_file = b.path("world_injection.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("world-injection", "Boundary crossing: real mathematics (the sieve) escapes the algebraic closure, certified");
    run_step.dependOn(&run_cmd.step);

    const eng_exe = b.addExecutable(.{
        .name = "invention_engine",
        .root_source_file = b.path("invention_engine.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(eng_exe);
    const run_eng = b.addRunArtifact(eng_exe);
    run_eng.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_eng.addArgs(args);
    const run_eng_step = b.step("invention-engine", "The closed inject→certify→promote loop: recombination vs certified invention, with compounding");
    run_eng_step.dependOn(&run_eng.step);

    // decoupled run steps (each compiles only its own file, so `zig build superopt` doesn't need the others)
    inline for (.{
        .{ "superopt", "superopt.zig", "Source B: verified superoptimization (external unknown + exhaustive verifier)" },
        .{ "real-data", "real_data.zig", "Source A: real dataset (corpus text) injects out-of-substrate structure" },
        .{ "certifier-filter", "certifier_filter.zig", "Source C: the certifier tames an unreliable generator (LLM stand-in)" },
        .{ "llm-proposer", "llm_proposer.zig", "Claude IS the generator: the LLM-in-the-loop experiment" },
        .{ "autonomous-engine", "autonomous_engine.zig", "The NEXT engine: autonomous, cheat-proof, self-contained" },
        .{ "compression-engine", "compression_engine.zig", "Wider DSL + compression-ratio certifier + live-LLM seed" },
        .{ "self-improve", "self_improve.zig", "The engine improving itself: LLM proposes upgrades, measurement certifies" },
        .{ "recursive-loop", "recursive_loop.zig", "Engine → successor → … the recursive self-improvement loop run to its bound" },
        .{ "real-invention", "real_invention.zig", "When is it a REAL invention engine? The engine discovers theorems it was not given" },
        .{ "dial-three", "dial_three.zig", "Turning the third dial: the certified loop on a genuine unknown (shortest addition chains)" },
        .{ "addition-frontier", "addition_frontier.zig", "Scaling dial 3: sound branch-and-bound pushes the certified addition-chain frontier past the toy range" },
        .{ "invent", "invent.zig", "The front-end: one loose human line in → certified invention out (LLM understands, engine proves)" },
        .{ "autonomous-inventor", "autonomous_inventor.zig", "The engine with NO neural layer: evolves reversible compression filters against real measurement, alone" },
        .{ "self-extending-inventor", "self_extending_inventor.zig", "Autonomy rung: the engine promotes its own winning compositions into reusable primitives and compounds them" },
        .{ "primitive-synthesizer", "primitive_synthesizer.zig", "Step 1 engine-native: invents genuinely-new primitive FORMS by synthesizing predictor programs (no LLM)" },
        .{ "intent-recognizer", "intent_recognizer.zig", "Step 2 engine-native: NL want → formal objective via a tiny trained perceptron over the engine's menu (no LLM)" },
        .{ "engine-repl", "engine_repl.zig", "Go back and forth with it: an interactive want→understand→invent→certify loop with persistent state, no LLM" },
        .{ "engine-chat", "engine_chat.zig", "Conversational layer: memory, social/meta intents, reasoning narration, clarifying questions, mood — no LLM" },
        .{ "intent-trained", "intent_trained.zig", "Train the understanding off English at scale: hundreds of generated phrases, held-out generalization, no hardcoded keywords" },
        .{ "babble", "babble.zig", "The honest reason replies are templated: a from-scratch small language model babbles; coherent generation needs an LLM" },
        .{ "tiered-learner", "tiered_learner.zig", "Learns as it goes: categorized data + ranked tiered memory (stolen from ghost_engine) + verifier labels, vs blind" },
        .{ "parametric-guide", "parametric_guide.zig", "A learned policy net over data features (trained on verifier labels) that generalizes to UNSEEN categories" },
        .{ "engine-live", "engine_live.zig", "Chat with it + LEARN FROM TERMINAL OUTPUTS (expectation-violation / RLVR-style), plus invention. No LLM" },
        .{ "engine-trained-chat", "engine_trained_chat.zig", "The fix: chat intent is TRAINED (classifier over generated English), not hardcoded keywords; routes novel phrasings" },
        .{ "grounded-language", "grounded_language.zig", "Three beyond-LLM language directions, measured: grounded-in-execution, compositional structure, continual acquisition" },
        .{ "terminal-ground", "terminal_ground.zig", "D1 for real: the engine RUNS commands, grounds word meaning in actual exit codes, predicts+verifies novel ones" },
        .{ "terminal-grind", "terminal_grind.zig", "Scaled: wide command vocab + rich outcomes grounded in REAL execution; puts a number on grounded actionable language" },
        .{ "terminal-grind-big", "terminal_grind_big.zig", "The bigger grind: hundreds of real commands, combinatorial phrasings, uni+bigram, stable number" },
        .{ "terminal-calibrated", "terminal_calibrated.zig", "Calibrated uncertainty as the model OWN softmax: peaked=answer, flat=ask; threshold calibrated not hardcoded" },
        .{ "terminal-sigil", "terminal_sigil.zig", "The sigil taken: ghost_engine ResonanceEMA self-calibrating confidence (energy + surprise/search bands), no hardcoded T" },
        .{ "engine-converse", "engine_converse.zig", "More natural conversation, no LLM: compositional assembly of human-written fragments, sigil-gated, varied, context-aware" },
        .{ "verified-generation", "verified_generation.zig", "The uncharted move: speech GATED by a sound verifier -- fluent-ish, novel, GUARANTEED TRUE, blocks hallucinations" },
        .{ "verified-language", "verified_language.zig", "Give it the language data and it CAN attempt idioms/ambiguity/concepts -- truthfully, or it refuses the unseen" },
        .{ "compositional-understanding", "compositional_understanding.zig", "Option 3 researched: compositional question parsing (math computed, definitions looked-up/learned) generalizes, no LLM" },
        .{ "compositional-atoms", "compositional_atoms.zig", "Stack verifiable atoms and MEASURE the answerable-slice widening over a fixed battery; generalizes, refuses the unverifiable, no LLM" },
        .{ "corpus-english", "corpus_english.zig", "Give it ~2M words of real English: distributional semantics (PPMI co-occurrence) — meaning EMERGES from counts, measured, no LLM" },
        .{ "semantic-generalize", "semantic_generalize.zig", "Synthesis: emergent vectors CLOSE the unseen-word gap — category coherence, calibrated held-out relatedness, infer-the-unknown, no LLM" },
        .{ "concept-structure", "concept_structure.zig", "What a king IS not just near: extract genus (Hearst IS-A), attributes (possessive/modifiers), measured attribute axes; assemble a definition, no LLM" },
        .{ "dictionary-define", "dictionary_define.zig", "The lever proven: same extractor on a DEFINITIONAL corpus (Webster's 1913) pulls the genus/definition the novels lacked, no LLM" },
        .{ "taxonomy-reason", "taxonomy_reason.zig", "Extract the IS-A graph from the dictionary, take transitive closure, REASON by inheritance (is a king a person?) with proof chains, no LLM" },
        .{ "wordnet-taxonomy", "wordnet_taxonomy.zig", "The proper data: WordNet's curated IS-A graph — clean chains to root ENTITY, lion->animal works, sound inheritance, no LLM" },
        .{ "network-train", "network_train.zig", "Network training: learn word meaning from the LIVE WEB as a stream (curl), bounded memory, raw bytes discarded, no hoarding, no LLM" },
        .{ "rune-stream", "rune_stream.zig", "Network training the RUNE-NATIVE way: tokens in, but memory is the rune ladder (promote by occ×context, TTL-prune noise), not a flat cap, no LLM" },
        .{ "rune-native", "rune_native.zig", "Runes ALL the way down: discover units from raw BYTES (byte-pair forge), no word-tokenizer — word/morpheme runes emerge, measured, no LLM" },
        .{ "sigil-speed", "sigil_speed.zig", "Sigil-gated retrieval (calibrated confidence, abstains on OOV/noise) + edge-case battery + measured tps-equivalent throughput, no LLM" },
        .{ "code-semantics", "code_semantics.zig", "The distributional+sigil stack on 39MB of CODE: identifier similarity (types cluster, const/var), related-vs-random, sigil, speed, no LLM" },
        .{ "universal-runes", "universal_runes.zig", "Rune-native (no tokens): forge runes from raw bytes + similarity over runes, on ANY script/code (English/Chinese/emoji/C++/Py/TS), no LLM" },
        .{ "rune-scale", "rune_scale.zig", "GB-on-GB stream training, rune-native: forge once, stream-encode via trie, co-occur at FLAT memory (real RSS measured), reads stdin, no tokens, no LLM" },
        .{ "multi-sense", "multi_sense.zig", "Architecture fix: MULTIPLE vectors per rune via context-clustering (multi-prototype) — polysemous runes split into senses, river-bank≠money-bank, no LLM" },
        .{ "multi-sense2", "multi_sense2.zig", "Auto-K per rune (silhouette) + MEASURED noise reduction (IDF context weighting) scored by purity vs true prose/code senses, no LLM" },
        .{ "sigil-engine", "sigil_engine.zig", "Sigil as universal decider (ResonanceEMA): engine decides answer/decline in its OWN runes via calibrated band, branches out via rune-walk, no hardcoded refusals, no LLM" },
        .{ "sigil-strong", "sigil_strong.zig", "Sigil-decider on STRONG embeddings: forge once + co-occur over ~12MB → crisp walks, sigil-gated, no hardcoded refusals, no LLM" },
        .{ "pseudoword-wsd", "pseudoword_wsd.zig", "Harder WSD with perfect ground truth: merge two words into a pseudoword, measure split purity by difficulty + IDF lever, no LLM" },
        .{ "branch-verify", "branch_verify.zig", "Branch out, not parrot: GENERATE multi-hop claims beyond training + a SOUND verifier certifies/rejects -- derives new true facts, no LLM" },
        .{ "contextual", "contextual.zig", "Capability experiment: non-parametric self-attention contextualization vs plain averaging on the WSD yardstick, measured, no LLM" },
        .{ "knn-lm", "knn_lm.zig", "Head-to-head: kNN retrieval predictor vs parametric n-gram, + the online-learning win on OOD data (frozen vs instant-adapt), no LLM" },
        .{ "learned-organ", "learned_organ.zig", "Add the missing organ: cheap learned readout (neg-sampling SGD, CPU) — lookup vs retrieval vs LEARNING on unseen contexts, no GPU, no LLM" },
        .{ "layers", "layers.zig", "Layer ablation: n-rune context (memorization) vs learned generalization organ — the sparsity principle + organ decomposition, no LLM" },
        .{ "richer-organ", "richer_organ.zig", "The richer organ: a learned MLP encoder over long context vs linear vs counting, next-rune, CPU/backprop, no GPU, no LLM" },
        .{ "sigil-organ", "sigil_organ.zig", "SIGIL not softmax: ReZero-residual learned organ (surprise-weighted LR) + selective prediction — CPU, no LLM" },
        .{ "attention-replacement", "attention_replacement.zig", "Replace attention: exact n-gram vs softmax self-attention vs HASH-routing (O(1) soft content-addressing) — next-rune, CPU, no GPU/LLM" },
        .{ "induction-recall", "induction_recall.zig", "Associative-recall capacity race: discrete-address vs softmax vs linear-attention vs LSH — the induction head as content addressing, CPU, no GPU/LLM" },
        .{ "induction-lm", "induction_lm.zig", "Synthesis: induction-copy (sharp recall) + hash-routing (soft) as ONE O(n) streaming next-rune predictor on real prose — attention's jobs without n², CPU, no GPU/LLM" },
        .{ "sigil-router", "sigil_router.zig", "SIGIL-gated committee of cheap routers (count backoff + induction + hash + organ) vs softmax/linear attention — beat attention's numbers, no softmax, CPU, no GPU/LLM" },
        .{ "attn-verify", "attn_verify.zig", "Verify the committee>attention gap: strengthen attention (multi-head × multi-epoch, frozen held-out) and find the TRUE multiple, CPU, no GPU/LLM" },
        .{ "hier-runes", "hier_runes.zig", "Depth via composition: hierarchical runes (bytes→runes→phrases→concepts) for multi-scale next-rune — does abstract context help, no attention, CPU, no GPU/LLM" },
        .{ "hier-deep", "hier_deep.zig", "Push depth: 4 composed levels + deeper local + joint couplings + induction, ablation ladder showing the committee climb — no attention, CPU, no GPU/LLM" },
        .{ "lm-bpc", "lm_bpc.zig", "Our rune stack vs a stolen GPT-2: bits-per-byte on the same held-out text (interpolated hierarchical backoff, prequential) — the fair capability metric, CPU, no GPU/LLM" },
        .{ "lm-bpc2", "lm_bpc2.zig", "Phase 1: interpolated absolute discounting (≈Kneser-Ney) to close the BPB gap to gpt2 — arg1=warm-start MB for data scaling, CPU, no GPU/LLM" },
        .{ "lm-bpc3", "lm_bpc3.zig", "Option 1: abs-disc + kNN/LSH embedding smoothing — the cheap-generalization BPB ceiling vs gpt2 (de-wrapped 1.0499), CPU, no GPU/LLM" },
        .{ "lm-bpc4", "lm_bpc4.zig", "Option 2: abs-disc + kNN over a LEARNED encoder (CBOW neg-sampling, no softmax) — does a learned key close the BPB gap to gpt2, CPU, no GPU/LLM" },
        .{ "lm-bpc5", "lm_bpc5.zig", "DATA SCALING: sweep warm-start size over ~40MB of novels — is the gap to gpt2 a data problem? arg1=MB, CPU, no GPU/LLM" },
    }) |spec| {
        const e = b.addExecutable(.{ .name = spec[0], .root_source_file = b.path(spec[1]), .target = target, .optimize = optimize });
        const rc = b.addRunArtifact(e);
        if (b.args) |args| rc.addArgs(args);
        const rs = b.step(spec[0], spec[2]);
        rs.dependOn(&rc.step);
    }
}
