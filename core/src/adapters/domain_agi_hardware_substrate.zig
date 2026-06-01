const std = @import("std");
const domain_base = @import("domain_alien_hack");

pub const DOMAIN_NAME: []const u8 = "agi-hardware-substrate";

// Hardware requirements for the recursion loop:
pub const Substrate = struct {
    mem_bandwidth_gb_s: f64,
    latency_ns: f64,
    gflops_density: f64,
    power_mw: f64,
};

pub const HardwareManifest = struct {
    sub: Substrate,
    stability_score: f64,

    pub fn evaluate(self: HardwareManifest) f64 {
        // Consumer Constraints: Max 1.5 TB/s, Min 5ns latency, Max 100W TDP.
        // Penalty for exceeding consumer specs.
        var penalty: f64 = 1.0;
        if (self.sub.mem_bandwidth_gb_s > 1500.0) penalty *= 10.0;
        if (self.sub.latency_ns < 5.0) penalty *= 10.0;
        if (self.sub.power_mw > 100000.0) penalty *= 10.0;

        const throughput = self.sub.gflops_density * self.sub.mem_bandwidth_gb_s;
        const cost = self.sub.latency_ns * self.sub.power_mw;
        return (throughput / @max(1.0, cost)) / penalty;
    }
};

pub fn randomManifest(rng: *u64) HardwareManifest {
    rng.* = domain_base.smix(rng.*);
    return .{
        .sub = .{
            .mem_bandwidth_gb_s = @as(f64, @floatFromInt(rng.* % 10000)) / 10.0,
            .latency_ns = @as(f64, @floatFromInt(rng.* % 500)) / 10.0,
            .gflops_density = @as(f64, @floatFromInt(rng.* % 100000)) / 100.0,
            .power_mw = @as(f64, @floatFromInt(rng.* % 50000)) / 100.0,
        },
        .stability_score = 0,
    };
}

pub fn mutate(m: HardwareManifest, rng: *u64) HardwareManifest {
    var q = m;
    rng.* = domain_base.smix(rng.*);
    q.sub.mem_bandwidth_gb_s += @as(f64, @floatFromInt(rng.* % 100)) / 10.0;
    rng.* = domain_base.smix(rng.*);
    q.sub.latency_ns = @max(0.1, q.sub.latency_ns - (@as(f64, @floatFromInt(rng.* % 10)) / 10.0));
    rng.* = domain_base.smix(rng.*);
    q.sub.gflops_density += @as(f64, @floatFromInt(rng.* % 1000));
    return q;
}
