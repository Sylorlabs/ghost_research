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
};

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
            .grid = [_]u8{0} ** 16,
            .failed = false,
            .step_count = 0,
            .params = params,
        };
    }

    pub fn step(self: *Environment, action: Action, rand: std.Random) void {
        const p = self.params;
        self.step_count += 1;

        if (self.failed) {
            // Auto-reset after failure
            self.grid = [_]u8{0} ** 16;
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

        // Dendrite short-circuit failure condition
        for (self.grid) |cell| {
            if (cell >= p.fail_threshold) {
                self.failed = true;
                break;
            }
        }
    }
};
