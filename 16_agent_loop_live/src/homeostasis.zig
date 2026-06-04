const std = @import("std");

pub const HomeostasisEngine = struct {
    stagnation: u32 = 0,
    velocity: f64 = 1.0,
    last_node_count: usize = 0,

    pub fn update(self: *HomeostasisEngine, current_nodes: usize) void {
        const delta = if (current_nodes > self.last_node_count) 
            current_nodes - self.last_node_count 
        else 
            self.last_node_count - current_nodes;

        // Velocity is the normalized rate of structural change
        self.velocity = @as(f64, @floatFromInt(delta)) / @max(1.0, @as(f64, @floatFromInt(current_nodes)));

        if (delta == 0) {
            self.stagnation += 1;
        } else {
            self.stagnation = 0;
        }
        self.last_node_count = current_nodes;
    }

    pub fn shouldReset(self: *HomeostasisEngine) bool {
        // Applying the autonomously discovered Alien Law of Escape:
        const stag_f = @as(f64, @floatFromInt(self.stagnation));
        const part1 = (stag_f + self.velocity) / 59.85;
        const part2 = (1.2 / @max(0.000001, self.velocity)) + 1.0;
        const alien_trigger = @log(@max(0.000001, @abs(part1))) * @log(@max(0.000001, @abs(part2)));

        return alien_trigger > 1.0;
    }
};
