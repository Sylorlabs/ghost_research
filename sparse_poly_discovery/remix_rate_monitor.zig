//! Rolling remix/novel rate monitor — T8-AG-21 core.
const std = @import("std");

pub const ALERT_THRESHOLD: f64 = 0.20;
pub const WINDOW: usize = 5;

pub const RunSample = struct {
    novel: usize,
    checked: usize,

    pub fn rate(self: RunSample) f64 {
        if (self.checked == 0) return 0;
        return @as(f64, @floatFromInt(self.novel)) / @as(f64, @floatFromInt(self.checked));
    }
};

pub const RollingMonitor = struct {
    samples: [WINDOW]RunSample = [_]RunSample{.{ .novel = 0, .checked = 0 }} ** WINDOW,
    n: usize = 0,

    pub fn push(self: *RollingMonitor, s: RunSample) void {
        if (self.n < WINDOW) {
            self.samples[self.n] = s;
            self.n += 1;
        } else {
            for (0..WINDOW - 1) |i| self.samples[i] = self.samples[i + 1];
            self.samples[WINDOW - 1] = s;
        }
    }

    pub fn meanRate(self: *const RollingMonitor) f64 {
        if (self.n == 0) return 0;
        var sum: f64 = 0;
        for (self.samples[0..self.n]) |s| sum += s.rate();
        return sum / @as(f64, @floatFromInt(self.n));
    }

    pub fn alertFired(self: *const RollingMonitor) bool {
        return self.n >= WINDOW and self.meanRate() < ALERT_THRESHOLD;
    }

    pub fn minRate(self: *const RollingMonitor) f64 {
        if (self.n == 0) return 0;
        var m: f64 = 1.0;
        for (self.samples[0..self.n]) |s| m = @min(m, s.rate());
        return m;
    }
};