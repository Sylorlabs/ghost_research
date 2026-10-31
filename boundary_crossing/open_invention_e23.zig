//! open_invention_e23.zig — EXPERIMENT E23: cross-corpus compression v2 (structurally similar).
//!
//! Question: does macro transfer work on structurally similar corpora (EN→EN held-out), not EN→ZH?
//! Protocol: train on train_dw_8mb; test structured held-out (de-wrapped Gutenberg family);
//!           require library>0; pass bar >0.1% held-out bytes saved with train library >4 macros.
//!
//! Extends open_invention_e9.zig via compression_invent.zig:
//!   - vote grid + pair candidates + stream self-extension on train
//!   - held-out: heldout_eval_dw.txt, heldout_eval.txt (same-script family, NOT Chinese)
//!
//! Run: zig build open-invention-e23 --release=fast

const ci = @import("compression_invent");

pub fn main() !void {
    const spec = ci.ExperimentSpec{
        .title = "EXPERIMENT E23: cross-corpus compression v2 (structurally similar corpora)",
        .objective_lines = &.{
            "question: macro transfer on structurally similar corpora (EN train → EN held-out), not EN→ZH?",
            "protocol: train on corpus/train_dw_8mb.txt; test de-wrapped Gutenberg held-out family.",
            "verifier = gzip size + exact round-trip. train uses vote+pair grid AND stream self-extension.",
        },
        .train_candidates = &.{"train_dw_8mb.txt"},
        .held_candidates = &.{
            "heldout_eval_dw.txt",
            "heldout_eval.txt",
        },
        .budget = .{
            .train_restarts = 8,
            .train_steps = 18,
            .held_restarts = 4,
            .held_steps = 10,
            .train_vote_chunks = 32,
            .max_lib = 24,
            .min_votes = 1,
        },
        .pass = .{
            .min_lib_macros = 5,
            .min_cross_pct = 0.1,
            .require_lib_nonempty = true,
        },
        .result_tag = "E23_RESULT",
        .result_doc = "docs/research/open_invention_e23.md",
        .train_seed = 0xE2300B23,
        .use_vote_library = true,
        .use_stream_library = true,
        .include_pair_candidates = true,
        .held_label = "structured held-out (same-family EN)",
    };
    try ci.runExperiment(spec);
}