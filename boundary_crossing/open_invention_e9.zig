//! open_invention_e9.zig — EXPERIMENT E9: real-data compression invention (cross-corpus generalization).
//!
//! Train: self-extending promotion on corpus/train_mix.txt or train_dw_8mb.txt (whichever loads first).
//! Test held-out family: chinese_train.txt, zh_held_dw.txt (if present).
//! Compare on held-out: base gzip vs no-promotion search vs self-extend (library frozen from train).
//!
//! Pass: self-extend beats no-promotion on held-out bytes (macros learned on train corpus generalize).
//!
//! Run: zig build open-invention-e9 --release=fast

const ci = @import("compression_invent");

pub fn main() !void {
    const spec = ci.ExperimentSpec{
        .title = "EXPERIMENT E9: real-data compression invention (cross-corpus generalization)",
        .objective_lines = &.{
            "objective: train self-extending promotion on EN/mixed corpus; test whether invented macros",
            "help held-out Chinese WITHOUT re-training. verifier = gzip size + exact round-trip.",
        },
        .train_candidates = &.{ "train_dw_8mb.txt", "train_mix.txt" },
        .held_candidates = &.{ "chinese_train.txt", "zh_held_dw.txt" },
        .budget = .{
            .train_restarts = 8,
            .train_steps = 18,
            .held_restarts = 4,
            .held_steps = 10,
            .train_vote_chunks = 16,
            .max_lib = 16,
            .min_votes = 2,
        },
        .pass = .{
            .min_lib_macros = 1,
            .min_cross_pct = 0.0,
            .require_lib_nonempty = true,
        },
        .result_tag = "E9_RESULT",
        .result_doc = "docs/research/open_invention_e9.md",
        .train_seed = 0xE900B009,
        .use_vote_library = true,
        .use_stream_library = false,
        .include_pair_candidates = false,
        .held_label = "held-out Chinese family",
    };
    try ci.runExperiment(spec);
}