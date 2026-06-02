const std = @import("std");
const hv = @import("hypervector.zig");
const connectome = @import("connectome.zig");
const env_mod = @import("environment.zig");
const vm = @import("vm.zig");

const Hypervector = hv.Hypervector;

/// Encodes a battery-cell Environment into an 8192-bit hypervector.
///
/// NOTE on the algebra: every term is XOR-combined (`bind`). Because `bind`
/// produces a vector *dissimilar* to its inputs, the state vector is a good
/// fingerprint for forward-model learning (does the whole vector match?) but its
/// individual components are NOT recoverable by Hamming distance. In particular
/// the failure FLAG cannot be read out: state = G XOR fail_val, majority commutes
/// with a constant XOR, so fail_val cancels in any prototype distance (verified by
/// tests.zig — an earlier "read the failure bit" claim was falsified there). What
/// model-based control below actually exploits is that under good control the cell
/// sits at a few RECURRING low-mass grids, so G repeats and the bundled safe/fail
/// prototypes capture that grid structure. (Moved here from ghost_daemon.zig so
/// the agent owns all of its learning state in one place.)
pub const EnvEncoder = struct {
    P: [16]Hypervector, // one role vector per grid cell (position)
    V: [256]Hypervector, // one filler vector per cell value (RANDOM: no metric structure)
    P_fail: Hypervector, // role for the failure flag
    V_true: Hypervector, // filler: failed = true
    V_false: Hypervector, // filler: failed = false

    // Ordinal (thermometer) value fillers: L[k] has a bit set iff that bit's random
    // level < k, so hamming(L[a],L[b]) ∝ |a-b|. This injects the METRIC structure the
    // random V[] lacks — the out-of-closure generator the band task needs to read
    // total mass (a sum/threshold the XOR substrate cannot otherwise expose).
    ordinal: bool,
    L: [17]Hypervector,

    pub fn init(rand: std.Random, ordinal: bool) EnvEncoder {
        var enc: EnvEncoder = undefined;
        for (0..16) |i| enc.P[i] = hv.initRandom(rand);
        for (0..256) |i| enc.V[i] = hv.initRandom(rand);
        enc.P_fail = hv.initRandom(rand);
        enc.V_true = hv.initRandom(rand);
        enc.V_false = hv.initRandom(rand);
        enc.ordinal = ordinal;
        if (ordinal) {
            // Only draws when ordinal==true, so the default (random) encoder's RNG
            // stream — and every downstream eval number — is byte-identical.
            var levels: [hv.D]u8 = undefined;
            for (0..hv.D) |i| levels[i] = rand.intRangeLessThan(u8, 0, 16);
            for (0..17) |k| {
                var vec: Hypervector = [_]u64{0} ** hv.Blocks;
                for (0..hv.D) |i| {
                    if (levels[i] < k) vec[i / 64] |= (@as(u64, 1) << @intCast(i % 64));
                }
                enc.L[k] = vec;
            }
        }
        return enc;
    }

    fn filler(self: *const EnvEncoder, value: u8) Hypervector {
        return if (self.ordinal) self.L[@min(value, 16)] else self.V[value];
    }

    pub fn encode(self: *const EnvEncoder, env: *const env_mod.Environment) Hypervector {
        var s = self.P_fail; // base vector
        for (0..16) |i| {
            s = hv.bind(s, hv.bind(self.P[i], self.filler(env.grid[i])));
        }
        const fail_val = if (env.failed) self.V_true else self.V_false;
        s = hv.bind(s, hv.bind(self.P_fail, fail_val));
        return s;
    }
};

/// How the agent picks its action each step.
pub const ActionMode = enum {
    random, // ignore the model, act randomly (the as-built behaviour)
    fixed, // always take `fixed_action` (for baseline policies)
    mb_safety, // model-based: pick the action whose predicted state is safest
    mb_surprise, // model-based: pick the most *predictable* action (min surprise)
    mb_mass, // nonlinear readout: regulate a learned scalar FEATURE toward the safe midpoint
    mb_plan, // mb_mass + H-step lookahead (rollout over the learned scalar model)
};

/// Candidate aggregate features for mb_mass. The point of the discovery
/// experiment: a generic feature search over these should DISCOVER that the SUM
/// (the out-of-closure generator) is the one enabling control, with the decoys
/// failing — autonomous escape rather than a human hard-coding "use total mass".
pub const FeatureKind = enum { sum, max_cell, first_cell, nonzero_count };

pub fn featureValue(grid: [16]u8, kind: FeatureKind) u32 {
    switch (kind) {
        .sum => {
            var m: u32 = 0;
            for (grid) |c| m += c;
            return m;
        },
        .max_cell => {
            var mx: u32 = 0;
            for (grid) |c| mx = @max(mx, c);
            return mx;
        },
        .first_cell => return grid[0],
        .nonzero_count => {
            var n: u32 = 0;
            for (grid) |c| {
                if (c > 0) n += 1;
            }
            return n;
        },
    }
}

pub const Config = struct {
    action_mode: ActionMode = .random,
    fixed_action: env_mod.Action = .rest,
    enable_learning: bool = true,
    enable_macros: bool = true,
    enable_meta: bool = true,
    epsilon: f32 = 0.10, // exploration rate for model-based modes
    pure_attraction: bool = false, // CP3: drop the 0.25 repulsion floor in rule learning
    ordinal_encoding: bool = false, // metric (thermometer) value fillers instead of random
    feature: FeatureKind = .sum, // which aggregate mb_mass regulates (discovery experiment)
};

pub const StepResult = struct {
    action: u8,
    prediction_error: f32,
    failed: bool,
    grid_mass: u32,
    active_tools: u32,
    meta_class: u8,
    executed_vm: [8]u8 = [_]u8{0} ** 8,
    executed_vm_len: u8 = 0,
};

const D_F: f32 = 8192.0;

fn popcountHV(v: Hypervector) u32 {
    const vec: @Vector(hv.Blocks, u64) = v;
    return @reduce(.Add, @as(@Vector(hv.Blocks, u32), @popCount(vec)));
}

/// Synchronous, deterministic predictive-coding agent.
///
/// One `step` = one discrete control cycle: choose action -> advance the world by
/// one tick -> observe -> measure prediction error -> learn. This replaces the
/// old real-time two-thread design (an env thread racing an inference thread over
/// a shared mutex), which was impossible to evaluate or reproduce.
pub const Agent = struct {
    allocator: std.mem.Allocator,
    cfg: Config,

    encoder: EnvEncoder,

    // Forward model: rule_vectors[a] is trained toward bind(S_t, S_next) for action a.
    rule_vectors: [3]Hypervector,
    action_vectors: [3]Hypervector,

    // Hierarchical / homeostatic machinery (faithful to the original daemon).
    action_matrix: connectome.ActionMatrix,
    vm_encoding: connectome.VMEncoding,
    meta_space: connectome.Layer1MetaSpace,
    exec_matrix: connectome.ExecutiveControlMatrix,

    plasticity_alpha: f32,
    homeostasis_threshold: f32,

    history_buffer: [100]Hypervector,
    history_idx: usize,
    latest_meta_class: u8,

    // Macro-execution state (was thread-local in the original loop).
    active_macro: ?*connectome.MacroConcept,
    macro_step: u8,
    macro_initial_state: ?Hypervector,

    // Streaming preference prototypes (bitwise-majority over observed states).
    // safe_counts/fail_counts hold per-bit set-counts so the majority vector can
    // be materialised on demand. Bundling (majority) preserves the recurring
    // grid structure that distinguishes safe from unsafe states — the signal the
    // single XOR-encoded state vector cannot expose by distance alone.
    safe_counts: []u32,
    fail_counts: []u32,
    safe_n: u32,
    fail_n: u32,
    safe_proto: Hypervector,
    fail_proto: Hypervector,
    all_proto: Hypervector,

    S_t: Hypervector,

    // Nonlinear (out-of-closure) mass readout for .mb_mass. Total grid mass is a SUM
    // the XOR/bundle substrate cannot expose, so the prototype-distance agent is
    // blind to the band. Here the agent learns a scalar model instead: the mean
    // mass-delta per action and the [min,max] of observed safe masses, then picks the
    // action whose predicted mass is nearest the safe midpoint. Same agent, one
    // out-of-closure feature added — the controlled test of the closure principle.
    cur_mass: u32,
    mass_delta: [3]f32,
    mass_dn: [3]u32,
    safe_mass_min: u32,
    safe_mass_max: u32,
    safe_mass_n: u32,

    pub fn init(allocator: std.mem.Allocator, rand: std.Random, cfg: Config, env: *const env_mod.Environment) !Agent {
        var self: Agent = undefined;
        self.allocator = allocator;
        self.cfg = cfg;
        self.encoder = EnvEncoder.init(rand, cfg.ordinal_encoding);
        for (0..3) |i| {
            self.rule_vectors[i] = hv.initRandom(rand);
            self.action_vectors[i] = hv.initRandom(rand);
        }
        self.action_matrix = connectome.ActionMatrix.init(rand);
        self.vm_encoding = connectome.VMEncoding.init(rand);
        self.meta_space = connectome.Layer1MetaSpace.init(rand);
        self.exec_matrix = connectome.ExecutiveControlMatrix.init(&self.vm_encoding);
        self.plasticity_alpha = 0.20;
        self.homeostasis_threshold = 0.05;
        self.history_idx = 0;
        self.latest_meta_class = 0;
        self.active_macro = null;
        self.macro_step = 0;
        self.macro_initial_state = null;

        self.safe_counts = try allocator.alloc(u32, 8192);
        self.fail_counts = try allocator.alloc(u32, 8192);
        @memset(self.safe_counts, 0);
        @memset(self.fail_counts, 0);
        self.safe_n = 0;
        self.fail_n = 0;
        self.safe_proto = [_]u64{0} ** hv.Blocks;
        self.fail_proto = [_]u64{0} ** hv.Blocks;
        self.all_proto = [_]u64{0} ** hv.Blocks;

        self.cur_mass = 0;
        self.mass_delta = .{ 0, 0, 0 };
        self.mass_dn = .{ 0, 0, 0 };
        self.safe_mass_min = std.math.maxInt(u32);
        self.safe_mass_max = 0;
        self.safe_mass_n = 0;

        self.S_t = self.encoder.encode(env);
        return self;
    }

    pub fn deinit(self: *Agent) void {
        self.allocator.free(self.safe_counts);
        self.allocator.free(self.fail_counts);
    }

    /// Re-seed perceptual state when the agent is dropped into a (possibly
    /// different) environment, without touching what it has learned (rules,
    /// prototypes). Used by the generalization harness to test transfer.
    pub fn beginEpisode(self: *Agent, env: *const env_mod.Environment) void {
        self.S_t = self.encoder.encode(env);
        self.active_macro = null;
        self.macro_step = 0;
        self.history_idx = 0;
    }

    fn updatePrototype(self: *Agent, state: Hypervector, failed: bool) void {
        const counts = if (failed) self.fail_counts else self.safe_counts;
        for (0..hv.Blocks) |b| {
            var word = state[b];
            const base = b * 64;
            while (word != 0) {
                const t = @ctz(word);
                counts[base + t] += 1;
                word &= word - 1;
            }
        }
        if (failed) self.fail_n += 1 else self.safe_n += 1;
    }

    fn materializePrototypes(self: *Agent) void {
        for (0..hv.Blocks) |b| {
            var safe_w: u64 = 0;
            var fail_w: u64 = 0;
            var all_w: u64 = 0;
            for (0..64) |bit| {
                const idx = b * 64 + bit;
                const one = @as(u64, 1) << @intCast(bit);
                if (self.safe_n > 0 and self.safe_counts[idx] * 2 > self.safe_n) safe_w |= one;
                if (self.fail_n > 0 and self.fail_counts[idx] * 2 > self.fail_n) fail_w |= one;
                const all_c = self.safe_counts[idx] + self.fail_counts[idx];
                const all_n = self.safe_n + self.fail_n;
                if (all_n > 0 and all_c * 2 > all_n) all_w |= one;
            }
            self.safe_proto[b] = safe_w;
            self.fail_proto[b] = fail_w;
            self.all_proto[b] = all_w;
        }
    }

    fn predictNext(self: *const Agent, action_idx: u8) Hypervector {
        return hv.bind(self.S_t, self.rule_vectors[action_idx]);
    }

    fn chooseAction(self: *Agent, rand: std.Random) u8 {
        if (self.active_macro) |m| {
            return if (self.macro_step == 0) m.action_a else m.action_b;
        }
        switch (self.cfg.action_mode) {
            .fixed => return @intFromEnum(self.cfg.fixed_action),
            .random => return rand.intRangeLessThan(u8, 0, 3),
            .mb_safety => {
                // No experience yet, or exploration roll -> act randomly.
                if ((self.safe_n + self.fail_n) == 0 or rand.float(f32) < self.cfg.epsilon)
                    return rand.intRangeLessThan(u8, 0, 3);
                self.materializePrototypes();
                var best: u8 = 0;
                var best_score: f32 = -1e9;
                for (0..3) |a| {
                    const vp = self.predictNext(@intCast(a));
                    // Far from the failure prototype AND close to the safe prototype = good.
                    const d_fail = if (self.fail_n > 0) hv.hammingDistance(vp, self.fail_proto) else 0.5;
                    const d_safe = if (self.safe_n > 0) hv.hammingDistance(vp, self.safe_proto) else 0.5;
                    const score = d_fail - d_safe;
                    if (score > best_score) {
                        best_score = score;
                        best = @intCast(a);
                    }
                }
                return best;
            },
            .mb_surprise => {
                if ((self.safe_n + self.fail_n) == 0 or rand.float(f32) < self.cfg.epsilon)
                    return rand.intRangeLessThan(u8, 0, 3);
                self.materializePrototypes();
                // Minimise expected surprise: pick the action whose predicted state is
                // most "familiar" (closest to the running mean of all seen states).
                var best: u8 = 0;
                var best_dist: f32 = 1e9;
                for (0..3) |a| {
                    const vp = self.predictNext(@intCast(a));
                    const d = hv.hammingDistance(vp, self.all_proto);
                    if (d < best_dist) {
                        best_dist = d;
                        best = @intCast(a);
                    }
                }
                return best;
            },
            .mb_mass => {
                // Out-of-closure readout: regulate total mass toward the midpoint of
                // the observed safe-mass range, using the learned per-action delta.
                if (self.safe_mass_n == 0 or rand.float(f32) < self.cfg.epsilon)
                    return rand.intRangeLessThan(u8, 0, 3);
                const setpoint = @as(f32, @floatFromInt(self.safe_mass_min + self.safe_mass_max)) / 2.0;
                const cm: f32 = @floatFromInt(self.cur_mass);
                var best: u8 = 0;
                var best_err: f32 = 1e9;
                for (0..3) |a| {
                    const pred = cm + self.mass_delta[a];
                    const e = @abs(pred - setpoint);
                    if (e < best_err) {
                        best_err = e;
                        best = @intCast(a);
                    }
                }
                return best;
            },
            .mb_plan => {
                // H-step lookahead over the learned scalar model: enumerate all 3^H
                // action sequences, score by out-of-band steps (+ a small centring
                // term), return the first action of the best sequence.
                if (self.safe_mass_n == 0 or rand.float(f32) < self.cfg.epsilon)
                    return rand.intRangeLessThan(u8, 0, 3);
                const lo: f32 = @floatFromInt(self.safe_mass_min);
                const hi: f32 = @floatFromInt(self.safe_mass_max);
                const setpoint = (lo + hi) / 2.0;
                const H: usize = 4;
                var total: usize = 1;
                for (0..H) |_| total *= 3;
                var best: u8 = 0;
                var best_cost: f32 = 1e9;
                var seq: usize = 0;
                while (seq < total) : (seq += 1) {
                    var m: f32 = @floatFromInt(self.cur_mass);
                    var x = seq;
                    var cost: f32 = 0;
                    var first: u8 = 0;
                    for (0..H) |stp| {
                        const a: usize = x % 3;
                        x /= 3;
                        if (stp == 0) first = @intCast(a);
                        m += self.mass_delta[a];
                        if (m < lo or m > hi) cost += 1.0;
                        cost += @abs(m - setpoint) * 0.01;
                    }
                    if (cost < best_cost) {
                        best_cost = cost;
                        best = first;
                    }
                }
                return best;
            },
        }
    }

    /// Honest replacement for the daemon's "VM synthesis" (which hardcoded a test
    /// program). Compiles a *legible* homeostatic policy to the VM ISA: under high
    /// surprise, widen the tolerance threshold and cool the learning rate so the
    /// forward model stops chasing transient shocks. Returns bytecode length.
    fn synthesizeHomeostaticProgram(error_rate: f32, buf: *[8]u8) usize {
        // threshold target grows with surprise: val * 0.05, clamp to a sane band.
        const thr_val: u8 = if (error_rate > 0.45) 4 else 3; // 0.20 or 0.15
        const alpha_val: u8 = if (error_rate > 0.45) 1 else 2; // 0.10 or 0.20
        buf[0] = @intFromEnum(vm.OpCode.SET_THRESHOLD);
        buf[1] = thr_val;
        buf[2] = @intFromEnum(vm.OpCode.SET_ALPHA);
        buf[3] = alpha_val;
        return 4;
    }

    fn macroLogic(self: *Agent, action_idx: u8, error_rate: f32, failed: bool, rand: std.Random, executed_vm: *[8]u8, executed_vm_len: *u8) void {
        if (self.active_macro) |macro| {
            self.macro_step += 1;
            if (self.macro_step >= 2) {
                if (error_rate < self.homeostasis_threshold and !failed and !macro.crystallized) {
                    macro.crystallized = true;
                    if (self.macro_initial_state) |init_s| {
                        self.action_matrix.accumulateAttractor(init_s, macro.vector, rand);
                    }
                }
                self.active_macro = null;
            }
            return;
        }

        // Shock event: a big prediction error with no macro active.
        if (error_rate > 0.35 and !failed) {
            const v_target = hv.bind(self.S_t, self.action_matrix.action_attractor);
            var best_macro: ?*connectome.MacroConcept = null;
            var best_dist: f32 = 1.0;
            for (0..self.action_matrix.macro_count) |i| {
                const m = &self.action_matrix.macros[i];
                if (m.crystallized) {
                    const dist = hv.hammingDistance(m.vector, v_target);
                    if (dist < 0.30 and dist < best_dist) {
                        best_dist = dist;
                        best_macro = m;
                    }
                }
            }
            if (best_macro) |m| {
                self.active_macro = m;
                self.macro_step = 0;
            } else if (error_rate > 0.45) {
                // Honest homeostatic synthesis (was a hardcoded test program).
                const code_len = synthesizeHomeostaticProgram(error_rate, executed_vm);
                executed_vm_len.* = @intCast(code_len);
                var ctx = vm.VMContext{
                    .alpha = &self.plasticity_alpha,
                    .threshold = &self.homeostasis_threshold,
                    .registers = [_]u8{0} ** 4,
                };
                vm.executeBytecode(&ctx, executed_vm[0..code_len]);
            } else {
                const a = rand.intRangeLessThan(u8, 0, 3);
                const b = rand.intRangeLessThan(u8, 0, 3);
                self.active_macro = self.action_matrix.compileMacro(a, b, self.action_vectors[a], self.action_vectors[b]);
                self.macro_step = 0;
                self.macro_initial_state = self.S_t;
                _ = action_idx;
            }
        }
    }

    fn metaLogic(self: *Agent, recorded_vec: Hypervector, rand: std.Random, executed_vm: *[8]u8, executed_vm_len: *u8) void {
        self.history_buffer[self.history_idx] = recorded_vec;
        self.history_idx += 1;
        if (self.history_idx < 100) return;

        const chronicle = self.meta_space.compressSensoryHistory(self.history_buffer[0..100], rand);
        const class = self.meta_space.classifyChronicle(chronicle);
        self.latest_meta_class = @intFromEnum(class);
        self.history_idx = 0;

        if (!self.cfg.enable_meta) return;
        if (class == .CHAOS_TREND or class == .OSCILLATION_TREND) {
            const exec_vec = self.exec_matrix.control_vectors[self.latest_meta_class];
            var out_code: [8]u8 = [_]u8{0} ** 8;
            const code_len = self.vm_encoding.unbindProgram(exec_vec, &out_code);
            var ctx = vm.VMContext{
                .alpha = &self.plasticity_alpha,
                .threshold = &self.homeostasis_threshold,
                .registers = [_]u8{0} ** 4,
            };
            vm.executeBytecode(&ctx, out_code[0..code_len]);
            @memcpy(executed_vm[0..code_len], out_code[0..code_len]);
            executed_vm_len.* = @intCast(code_len);
        }
    }

    /// Q5 instrument: the greedy action the safety rule would pick, ignoring
    /// exploration. Returns 0 if there is no experience yet.
    pub fn probeSafetyAction(self: *Agent) u8 {
        if ((self.safe_n + self.fail_n) == 0) return 0;
        self.materializePrototypes();
        var best: u8 = 0;
        var best_score: f32 = -1e9;
        for (0..3) |a| {
            const vp = self.predictNext(@intCast(a));
            const d_fail = if (self.fail_n > 0) hv.hammingDistance(vp, self.fail_proto) else 0.5;
            const d_safe = if (self.safe_n > 0) hv.hammingDistance(vp, self.safe_proto) else 0.5;
            const score = d_fail - d_safe;
            if (score > best_score) {
                best_score = score;
                best = @intCast(a);
            }
        }
        return best;
    }

    /// Q5 instrument: the greedy action the surprise rule would pick (most
    /// predictable / closest to the running mean state).
    pub fn probeSurpriseAction(self: *Agent) u8 {
        if ((self.safe_n + self.fail_n) == 0) return 0;
        self.materializePrototypes();
        var best: u8 = 0;
        var best_dist: f32 = 1e9;
        for (0..3) |a| {
            const vp = self.predictNext(@intCast(a));
            const d = hv.hammingDistance(vp, self.all_proto);
            if (d < best_dist) {
                best_dist = d;
                best = @intCast(a);
            }
        }
        return best;
    }

    pub fn step(self: *Agent, env: *env_mod.Environment, rand: std.Random) StepResult {
        self.cur_mass = featureValue(env.grid, self.cfg.feature); // the chosen aggregate
        const action_idx = self.chooseAction(rand);
        const action: env_mod.Action = @enumFromInt(action_idx);
        const V_pred = self.predictNext(action_idx);

        env.step(action, rand);
        const S_next = self.encoder.encode(env);
        const failed = env.failed;

        var grid_mass: u32 = 0;
        for (env.grid) |c| grid_mass += c;

        // Learn the scalar feature model (for .mb_mass): running-mean per-action
        // delta of the chosen feature and the [min,max] range over safe states.
        {
            const feat_next = featureValue(env.grid, self.cfg.feature);
            const d = @as(f32, @floatFromInt(feat_next)) - @as(f32, @floatFromInt(self.cur_mass));
            self.mass_dn[action_idx] += 1;
            const n: f32 = @floatFromInt(self.mass_dn[action_idx]);
            self.mass_delta[action_idx] += (d - self.mass_delta[action_idx]) / n;
            if (!failed) {
                self.safe_mass_min = @min(self.safe_mass_min, feat_next);
                self.safe_mass_max = @max(self.safe_mass_max, feat_next);
                self.safe_mass_n += 1;
            }
        }

        const err_vec = hv.bind(V_pred, S_next);
        const error_rate = @as(f32, @floatFromInt(popcountHV(err_vec))) / D_F;

        if (self.cfg.enable_learning) {
            const target_rule = hv.bind(self.S_t, S_next);
            if (error_rate > self.homeostasis_threshold and self.active_macro == null) {
                if (self.cfg.pure_attraction) {
                    connectome.attractVectorsPtrPure(rand, &self.rule_vectors[action_idx], &target_rule, self.plasticity_alpha);
                } else {
                    connectome.attractVectorsPtr(rand, &self.rule_vectors[action_idx], &target_rule, self.plasticity_alpha);
                }
            }
            self.updatePrototype(S_next, failed);
        }

        var executed_vm: [8]u8 = [_]u8{0} ** 8;
        var executed_vm_len: u8 = 0;
        if (self.cfg.enable_macros) {
            self.macroLogic(action_idx, error_rate, failed, rand, &executed_vm, &executed_vm_len);
        }

        self.S_t = S_next;

        const recorded_vec = if (self.active_macro) |m| m.vector else self.action_vectors[action_idx];
        self.metaLogic(recorded_vec, rand, &executed_vm, &executed_vm_len);

        var active_tools: u32 = 0;
        for (0..self.action_matrix.macro_count) |i| {
            if (self.action_matrix.macros[i].crystallized) active_tools += 1;
        }

        return .{
            .action = action_idx,
            .prediction_error = error_rate,
            .failed = failed,
            .grid_mass = grid_mass,
            .active_tools = active_tools,
            .meta_class = self.latest_meta_class,
            .executed_vm = executed_vm,
            .executed_vm_len = executed_vm_len,
        };
    }
};
