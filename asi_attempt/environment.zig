const std = @import("std");

pub const Action = enum(u8) {
    charge = 0,
    discharge = 1,
    rest = 2,
};

pub const Environment = struct {
    grid: [16]u8,
    failed: bool,
    step_count: u32,

    pub fn init() Environment {
        return .{
            .grid = [_]u8{0} ** 16,
            .failed = false,
            .step_count = 0,
        };
    }

    pub fn step(self: *Environment, action: Action) void {
        self.step_count += 1;
        
        if (self.failed) {
            // Auto-reset after failure
            self.grid = [_]u8{0} ** 16;
            self.failed = false;
            return;
        }
        
        if (self.step_count > 0 and self.step_count % 500 == 0) {
            // Systemic Shock Event!
            self.grid[2] +|= 4;
            self.grid[7] +|= 4;
            self.grid[13] +|= 4;
        }
        
        if (self.step_count > 750) {
            // Metacognitive Volatility Event
            self.grid[self.step_count % 16] +|= 2;
        }

        switch (action) {
            .charge => {
                // Ions move towards the anode (index 0) and accumulate
                var i: usize = 15;
                while (i > 0) : (i -= 1) {
                    if (self.grid[i] < 10) {
                        self.grid[i-1] +|= 1;
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
                        self.grid[i+1] +|= 1;
                    }
                }
                if (self.grid[15] > 0) self.grid[15] -= 1;
            },
            .rest => {
                // Diffusion / relaxation
                for (&self.grid) |*cell| {
                    if (cell.* > 0) cell.* -= 1;
                }
            }
        }

        // Dendrite short-circuit failure condition
        for (self.grid) |cell| {
            if (cell >= 5) {
                self.failed = true;
                break;
            }
        }
    }
};
