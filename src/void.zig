const std = @import("std");
const flame = @import("flame");

pub const VoidEngine = struct {
    state: flame.FlameState,

    pub fn init(seed: u64) VoidEngine {
        return .{
            .state = flame.FlameState.init(seed),
        };
    }

    pub fn ingestTextSequence(self: *VoidEngine, seed: u64, text: []const u8, len: usize) void {
        _ = seed;
        var h = self.state.kernel;
        for (0..len) |idx| {
            const b = text[idx % text.len];
            h = flame.splitMix64(h ^ b ^ idx);
            // Sparse routing: each character touches 8 chambers determined by hash.
            // Contribution is bounded (+/-b), so chamber values stay in the same
            // scale as the law targets and different prompts trigger different laws.
            var rh = h;
            for (0..8) |_| {
                rh = flame.splitMix64(rh);
                const chamber_idx = rh % flame.ChamberCount;
                const sign: i128 = if (rh & (1 << 63) == 0) 1 else -1;
                self.state.chamber[chamber_idx] += @as(i128, b) * sign;
            }
            h = rh;
        }
        self.state.closure_error = flame.closureError(&self.state);
    }
    
    pub fn ingestSequence(self: *VoidEngine, seed: u64, len: usize) void {
        var h = seed ^ self.state.kernel;
        for (0..len) |idx| {
            h = flame.splitMix64(h ^ @as(u64, @intCast(idx)));
            for (0..flame.ChamberCount) |i| {
                const shift_val = @as(i128, @intCast((h >> @as(u6, @intCast(i * 3 % 60))) & 0xFFFF));
                self.state.chamber[i] = (self.state.chamber[i] ^ shift_val) + @as(i128, @intCast(h % 2048));
            }
        }
        self.state.closure_error = flame.closureError(&self.state);
    }

    pub fn shapeTextPressure(self: *VoidEngine, seed: u64, text: []const u8) void {
        const h = flame.textHash(text) ^ flame.splitMix64(seed);
        const base_magnitude = @as(i64, @intCast(12_600_000_000 + (h % 24_200_000_000)));
        for (0..flame.ChamberCount) |i| {
            const phase = (h >> @as(u6, @intCast(i % 60))) & 1;
            const sign: i64 = if (phase == 0) 1 else -1;
            const mag = @divTrunc(base_magnitude, @as(i64, @intCast(i + 1)));
            
            var low: i64 = @truncate(self.state.chamber[i]);
            var high: i64 = @as(i64, @truncate(self.state.chamber[i] >> 64));

            low +|= mag * sign;
            high +|= mag * sign;

            const u_low: u64 = @bitCast(low);
            const u_high: u64 = @bitCast(high);
            self.state.chamber[i] = @bitCast((@as(u128, u_high) << 64) | @as(u128, u_low));
        }
        self.state.scar_bank[h % flame.ScarCount] ^= flame.splitMix64(h ^ 0x0DE7E4B4E9B4D825);
        self.state.closure_error = flame.closureError(&self.state);
    }

    pub fn maybeInventText(self: *const VoidEngine, text: []const u8, generation: u32) ?flame.InventionCandidate {
        const control_closure = flame.closureError(&self.state);
        if (control_closure == 0) return null;
        var best: ?flame.InventionCandidate = null;
        const context_hash = flame.textHash(text);
        const state_fingerprint = residualFingerprint(&self.state) ^ context_hash;
        const NullScar: u64 = 0x3563447E3EBAEF14;
        const medians = calculateMedians(&self.state);
        const VoidBranches = 256; 
        for (0..VoidBranches) |branch| {
            var trial = self.state;
            // Clear or reset masks to self.state's masks to ensure no leak
            trial.locked_low = self.state.locked_low;
            trial.locked_high = self.state.locked_high;
            
            const branch_seed = flame.splitMix64(state_fingerprint ^ branch ^ generation);
            for (0..flame.ChamberCount) |i| {
                var low: i64 = @truncate(trial.chamber[i]);
                var high: i64 = @as(i64, @truncate(trial.chamber[i] >> 64));

                const gradient_low = low - medians.low;
                const gradient_high = high - medians.high;

                const scar_mix = @as(i64, @intCast((NullScar >> @as(u6, @intCast(i * 6 % 60))) & 0xFFFFFFFF));
                const branch_mix = @as(i64, @intCast((branch_seed >> @as(u6, @intCast(i * 5 % 60))) & 0xFFFFFFFF));
                
                if (!trial.locked_low[i]) {
                    low = medians.low - @divTrunc(gradient_low * 2, 1) + scar_mix ^ branch_mix;
                }
                if (!trial.locked_high[i]) {
                    high = medians.high - @divTrunc(gradient_high * 2, 1) + scar_mix ^ branch_mix;
                }

                const u_low: u64 = @bitCast(low);
                const u_high: u64 = @bitCast(high);
                trial.chamber[i] = @bitCast((@as(u128, u_high) << 64) | @as(u128, u_low));
            }
            for (0..500) |pass| {
                for (flame.Laws) |law| {
                    var low_a: i64 = @truncate(trial.chamber[law.a]);
                    var high_a: i64 = @as(i64, @truncate(trial.chamber[law.a] >> 64));
                    var low_b: i64 = @truncate(trial.chamber[law.b]);
                    var high_b: i64 = @as(i64, @truncate(trial.chamber[law.b] >> 64));

                    const got_low = law.ca * @as(i128, low_a) + law.cb * @as(i128, low_b);
                    const err_low = law.t - got_low;

                    const got_high = law.ca * @as(i128, high_a) + law.cb * @as(i128, high_b);
                    const err_high = law.t - got_high;

                    const denom = law.ca * law.ca + law.cb * law.cb;
                    
                    if (denom != 0) {
                        const dampener = @as(i128, @intCast(1 + (pass / 10)));
                        if (err_low != 0) {
                            const da_low = @divTrunc(err_low * law.ca, denom * dampener);
                            const db_low = @divTrunc(err_low * law.cb, denom * dampener);
                            if (!trial.locked_low[law.a]) low_a +|= @as(i64, @intCast(@max(-1_000_000_000_000, @min(1_000_000_000_000, da_low))));
                            if (!trial.locked_low[law.b]) low_b +|= @as(i64, @intCast(@max(-1_000_000_000_000, @min(1_000_000_000_000, db_low))));
                        }

                        if (err_high != 0) {
                            const da_high = @divTrunc(err_high * law.ca, denom * dampener);
                            const db_high = @divTrunc(err_high * law.cb, denom * dampener);
                            if (!trial.locked_high[law.a]) high_a +|= @as(i64, @intCast(@max(-1_000_000_000_000, @min(1_000_000_000_000, da_high))));
                            if (!trial.locked_high[law.b]) high_b +|= @as(i64, @intCast(@max(-1_000_000_000_000, @min(1_000_000_000_000, db_high))));
                        }
                    }

                    const u_low_a: u64 = @bitCast(low_a);
                    const u_high_a: u64 = @bitCast(high_a);
                    trial.chamber[law.a] = @bitCast((@as(u128, u_high_a) << 64) | @as(u128, u_low_a));

                    const u_low_b: u64 = @bitCast(low_b);
                    const u_high_b: u64 = @bitCast(high_b);
                    trial.chamber[law.b] = @bitCast((@as(u128, u_high_b) << 64) | @as(u128, u_low_b));
                }
            }
            const closure_after = flame.closureError(&trial);
            const required_improvement = (control_closure * 99) / 100;
            if (closure_after + required_improvement >= control_closure) continue;
            const candidate = flame.InventionCandidate{
                .child_mark = self.state.kernel ^ branch_seed,
                .chamber_snapshot = trial.chamber,
                .closure_before = control_closure,
                .closure_after = closure_after,
                .closure_delta = @as(i128, @intCast(closure_after)) - @as(i128, @intCast(control_closure)),
                .scar = NullScar ^ branch_seed,
                .trigger_edge = 0,
                .generation = generation,
                .signature = [_]u64{0} ** flame.SignatureWords,
            };
            if (best == null or candidate.closure_after < best.?.closure_after) {
                best = candidate;
            }
        }
        return best;
    }
};

const Medians = struct { low: i64, high: i64 };

fn calculateMedians(state: *const flame.FlameState) Medians {
    var sorted_low: [flame.ChamberCount]i64 = undefined;
    var sorted_high: [flame.ChamberCount]i64 = undefined;

    for (0..flame.ChamberCount) |i| {
        sorted_low[i] = @truncate(state.chamber[i]);
        sorted_high[i] = @as(i64, @truncate(state.chamber[i] >> 64));
    }

    // Sort low
    for (0..flame.ChamberCount - 1) |i| {
        for (i + 1..flame.ChamberCount) |j| {
            if (sorted_low[j] < sorted_low[i]) {
                const temp = sorted_low[i];
                sorted_low[i] = sorted_low[j];
                sorted_low[j] = temp;
            }
        }
    }

    // Sort high
    for (0..flame.ChamberCount - 1) |i| {
        for (i + 1..flame.ChamberCount) |j| {
            if (sorted_high[j] < sorted_high[i]) {
                const temp = sorted_high[i];
                sorted_high[i] = sorted_high[j];
                sorted_high[j] = temp;
            }
        }
    }

    return .{
        .low = sorted_low[flame.ChamberCount / 2],
        .high = sorted_high[flame.ChamberCount / 2],
    };
}

pub fn splitMix64(x: u64) u64 {
    var z = x +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

pub fn textHash(text: []const u8) u64 {
    var h: u64 = 0x811C9DC5;
    for (text) |b| {
        h = (h ^ @as(u64, b)) *% 0x01000193;
    }
    return h;
}

fn residualFingerprint(state: *const flame.FlameState) u64 {
    var h: u64 = 0x811C9DC5;
    for (state.chamber) |val| {
        const uval: u128 = @bitCast(val);
        h = (h ^ @as(u64, @truncate(uval))) *% 0x01000193;
        h = (h ^ @as(u64, @truncate(uval >> 64))) *% 0x01000193;
    }
    return h;
}
