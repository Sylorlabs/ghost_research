const std = @import("std");

pub const Action = enum(u8) {
    charge = 0,
    discharge = 1,
    rest = 2,
};

/// Tunable dynamics so the same agent can be tested across a TRAIN regime and
/// HELD-OUT regimes (generalization). The defaults reproduce the original fixed
/// environment exactly, so Environment.init() is unchanged for the live daemon
/// and the main eval harness.
pub const TaskParams = struct {
    fail_threshold: u8 = 5, // a cell >= this is a dendrite short-circuit
    shock_period: u32 = 500, // systemic shock every N steps (0 = never)
    shock_mag: u8 = 4, // magnitude added to cells [2,7,13] on a shock
    volatility_after: u32 = 750, // after this step, drip volatility each tick
    volatility_mag: u8 = 2, // magnitude of the per-step volatility drip
    noise_prob: f32 = 0.0, // stochastic: per-step chance to bump a random cell
    noise_mag: u8 = 1, // magnitude of the stochastic bump
    nonlinear: bool = false, // add a multiplicative neighbour coupling (non-affine)
    min_mass: u32 = 0, // homeostatic FLOOR: if >0, total grid mass < min_mass is an
    // UNDERCHARGE failure. `rest` (and a disturbance-free `discharge`) drain below it.
    max_mass: u32 = 0, // homeostatic CEILING: if >0, total grid mass > max_mass is an
    // OVERCHARGE failure. `charge` piles above it. Together [min_mass, max_mass] is a
    // two-sided band that NO constant policy can hold — competence becomes measurable
    // above trivial. Best run with shocks/volatility off (those refill `discharge`).
    min_left_mass: u32 = 0, // two-sided band on the LEFT HALF (cells 0..7). For tasks
    max_left_mass: u32 = 0, // where total-mass readout is insufficient: knowing sum alone
    // does NOT tell you if left_mass is in range. Agent needs a 2D readout or a feature
    // that captures distribution, not just total. Default 0 = constraint off.
};

// Seed (and post-failure reset) the grid INSIDE the band so it doesn't instantly
// fail. Targets the band midpoint, spread evenly, each cell below fail_threshold.
// Returns all-zeros when min_mass==0, so the default environment is byte-identical.
fn targetMass(p: TaskParams) u32 {
    if (p.min_mass == 0) return 0;
    if (p.max_mass > 0) return (p.min_mass + p.max_mass) / 2;
    return p.min_mass + 16; // floor-only: start a bit above the floor
}

fn seededGrid(p: TaskParams) [16]u8 {
    const tm = targetMass(p);
    if (tm == 0) return [_]u8{0} ** 16;
    const cap: u32 = if (p.fail_threshold > 1) p.fail_threshold - 1 else 1;
    const base = tm / 16;
    const rem = tm % 16;
    var g: [16]u8 = undefined;
    for (0..16) |i| {
        const v = @min(base + (if (i < rem) @as(u32, 1) else 0), cap);
        g[i] = @intCast(v);
    }
    return g;
}

pub const Environment = struct {
    grid: [16]u8,
    failed: bool,
    step_count: u32,
    params: TaskParams,

    pub fn init() Environment {
        return initWith(.{});
    }

    pub fn initWith(params: TaskParams) Environment {
        return .{
            .grid = seededGrid(params), // all-zeros when min_mass==0 (default unchanged)
            .failed = false,
            .step_count = 0,
            .params = params,
        };
    }

    pub fn step(self: *Environment, action: Action, rand: std.Random) void {
        const p = self.params;
        self.step_count += 1;

        if (self.failed) {
            // Auto-reset after failure (back into the band when min_mass>0)
            self.grid = seededGrid(p);
            self.failed = false;
            return;
        }

        if (p.shock_period > 0 and self.step_count % p.shock_period == 0) {
            // Systemic Shock Event!
            self.grid[2] +|= p.shock_mag;
            self.grid[7] +|= p.shock_mag;
            self.grid[13] +|= p.shock_mag;
        }

        if (self.step_count > p.volatility_after) {
            // Metacognitive Volatility Event
            self.grid[self.step_count % 16] +|= p.volatility_mag;
        }

        if (p.noise_prob > 0.0 and rand.float(f32) < p.noise_prob) {
            // Stochastic disturbance (held-out regimes only)
            self.grid[rand.intRangeLessThan(usize, 0, 16)] +|= p.noise_mag;
        }

        switch (action) {
            .charge => {
                // Ions move towards the anode (index 0) and accumulate
                var i: usize = 15;
                while (i > 0) : (i -= 1) {
                    if (self.grid[i] < 10) {
                        self.grid[i - 1] +|= 1;
                    }
                }
                self.grid[15] +|= 1; // source
            },
            .discharge => {
                // Ions move towards cathode (index 15)
                var i: usize = 0;
                while (i < 15) : (i += 1) {
                    if (self.grid[i] > 0) {
                        self.grid[i] -= 1;
                        self.grid[i + 1] +|= 1;
                    }
                }
                if (self.grid[15] > 0) self.grid[15] -= 1;
            },
            .rest => {
                // Diffusion / relaxation
                for (&self.grid) |*cell| {
                    if (cell.* > 0) cell.* -= 1;
                }
            },
        }

        if (p.nonlinear) {
            // A genuinely non-affine coupling: each cell gains the bitwise-AND of
            // its two neighbours' levels. AND is nonlinear over the cell values,
            // so a GF(2)-linear (XOR/permute) forward model cannot represent this
            // transition exactly. Used by the expressiveness-ceiling probe.
            var add: [16]u8 = [_]u8{0} ** 16;
            for (0..16) |i| {
                const l = self.grid[(i + 15) % 16];
                const r = self.grid[(i + 1) % 16];
                add[i] = (l & r) & 0x3; // bounded, nonlinear in neighbours
            }
            for (0..16) |i| self.grid[i] +|= add[i];
        }

        // Dendrite short-circuit failure condition (overcharge: a cell too high)
        for (self.grid) |cell| {
            if (cell >= p.fail_threshold) {
                self.failed = true;
                break;
            }
        }

        // Homeostatic band failure: total mass out of [min_mass, max_mass].
        if (!self.failed and (p.min_mass > 0 or p.max_mass > 0)) {
            var mass: u32 = 0;
            for (self.grid) |c| mass += c;
            if (p.min_mass > 0 and mass < p.min_mass) self.failed = true;
            if (p.max_mass > 0 and mass > p.max_mass) self.failed = true;
        }
        // Left-half band failure: left_mass out of [min_left_mass, max_left_mass].
        if (!self.failed and (p.min_left_mass > 0 or p.max_left_mass > 0)) {
            var lm: u32 = 0;
            for (self.grid[0..8]) |c| lm += c;
            if (p.min_left_mass > 0 and lm < p.min_left_mass) self.failed = true;
            if (p.max_left_mass > 0 and lm > p.max_left_mass) self.failed = true;
        }
    }
};
