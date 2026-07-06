//! EXP-6 — minimal learned candidate policy for unified invention.
//!
//! Perceptron scorer over cheap candidate features (probe correlation, hardness class,
//! inner type), trained online from verifier labels (certified escape vs failed).
//! Guides expensive certify() calls via top-k ranking.
//!
//! Run benchmark: zig build learned-guide-test --release=fast

const std = @import("std");

pub const NFEAT: usize = 3;
pub const TOP_K_FORGE: usize = 5;
pub const TOP_K_WORLD: usize = 3;
pub const TOP_K_DEFAULT: usize = TOP_K_FORGE;

pub const TaskHardness = enum(u8) {
    single_sufficient = 0,
    unknown = 1,
    q38_compound = 2,
};

pub const InnerType = enum(u8) {
    monomial = 0,
    spectral = 1,
    walsh = 2,
    clifford = 3,
    world_sum = 4,
    world_sign = 5,
};

pub const CandFeatures = struct {
    probe_corr: f64,
    hardness: TaskHardness,
    inner: InnerType,

    pub fn toVec(self: CandFeatures, out: []f64) void {
        out[0] = self.probe_corr;
        out[1] = @floatFromInt(@intFromEnum(self.hardness));
        out[2] = @floatFromInt(@intFromEnum(self.inner));
    }
};

pub const LogEntry = struct {
    features: CandFeatures,
    certified: bool,
    cov_after: f64,
    r2: f64,
};

pub const Guide = struct {
    w: [NFEAT + 1]f32 = .{0} ** (NFEAT + 1),
    entries: std.ArrayList(LogEntry),
    train_steps: usize = 0,

    pub fn init(alloc: std.mem.Allocator) Guide {
        return .{ .entries = std.ArrayList(LogEntry).init(alloc) };
    }

    pub fn deinit(self: *Guide) void {
        self.entries.deinit();
    }

    pub fn score(self: Guide, f: CandFeatures) f32 {
        var feats: [NFEAT]f64 = undefined;
        f.toVec(&feats);
        var z: f32 = self.w[NFEAT];
        for (0..NFEAT) |j| z += self.w[j] * @as(f32, @floatCast(feats[j]));
        return z;
    }

    /// Online perceptron update from verifier label (certified = +1, failed = -1).
    pub fn train(self: *Guide, f: CandFeatures, certified: bool) void {
        var feats: [NFEAT]f64 = undefined;
        f.toVec(&feats);
        const y: f32 = if (certified) 1.0 else -1.0;
        var z: f32 = self.w[NFEAT];
        for (0..NFEAT) |j| z += self.w[j] * @as(f32, @floatCast(feats[j]));
        const pred: f32 = if (z >= 0) 1.0 else -1.0;
        if (pred == y) return;
        const lr: f32 = 0.15;
        for (0..NFEAT) |j| self.w[j] += lr * y * @as(f32, @floatCast(feats[j]));
        self.w[NFEAT] += lr * y;
        self.train_steps += 1;
    }

    pub fn logAndTrain(self: *Guide, f: CandFeatures, certified: bool, cov_after: f64, r2: f64) !void {
        try self.entries.append(.{
            .features = f,
            .certified = certified,
            .cov_after = cov_after,
            .r2 = r2,
        });
        self.train(f, certified);
    }

    pub fn printLog(self: Guide, out: anytype) !void {
        try out.print("  guide log ({d} entries, {d} train steps):\n", .{ self.entries.items.len, self.train_steps });
        for (self.entries.items) |e| {
            try out.print("    corr={d:.3} hard={d} inner={d} → {s} cov={d:.3} r2={d:.3}\n", .{
                e.features.probe_corr,
                @intFromEnum(e.features.hardness),
                @intFromEnum(e.features.inner),
                if (e.certified) "CERT" else "fail",
                e.cov_after,
                e.r2,
            });
        }
    }
};

/// Classify substrate hardness (mirrors verify_learn_invent / hardness_router).
pub fn classifyHardness(mono_best: f64, extremal_best: f64) TaskHardness {
    const single_sufficient: f64 = 0.70;
    const mono_saturate: f64 = 0.55;
    if (mono_best >= single_sufficient or extremal_best >= single_sufficient) return .single_sufficient;
    if (mono_best <= mono_saturate and extremal_best <= mono_saturate) return .q38_compound;
    return .unknown;
}

pub fn innerFromFeatureTag(tag: anytype) InnerType {
    return switch (tag) {
        .monomial, .pair_relation => .monomial,
        .spectral_count => .spectral,
        .walsh => .walsh,
        .clifford_g2 => .clifford,
        .world_sum_mod => .world_sum,
        .world_sign_mod => .world_sign,
    };
}