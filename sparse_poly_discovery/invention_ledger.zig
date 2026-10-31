//! T8-AG-18 — mmap-style promotion ledger for invention loop audit.
//!
//! Records every tax-gated promote attempt: feature, basis version, survivor flag.

const std = @import("std");
const ui = @import("unified_invention.zig");

pub const MAGIC: u32 = 0x4C454447; // "LEDG"
pub const VERSION: u32 = 1;

pub const PromotionRecord = extern struct {
    seq: u64,
    tax_basis_version: u32,
    feature_tag: u8,
    feature_param: u64,
    cert_ok: u8,
    tax_survivor: u8,
    remix_family: u8,
    _pad: u8 = 0,
    test_acc_bits: u32,
    cov_before_bits: u32,
    cov_after_bits: u32,
};

pub var enabled: bool = false;
pub var path: []const u8 = "/tmp/tier8-swarm/invention_ledger.bin";

var g_seq: u64 = 0;
var g_file: ?std.fs.File = null;
var g_records: [256]PromotionRecord = undefined;
var g_n: usize = 0;

fn f64ToBits(v: f64) u32 {
    return @as(u32, @truncate(@as(u64, @bitCast(v))));
}

fn featureTag(f: ui.Feature) u8 {
    return @intFromEnum(std.meta.activeTag(f));
}

fn featureParam(f: ui.Feature) u64 {
    return switch (f) {
        .monomial => |m| m,
        .pair_relation => |ij| (@as(u64, ij.i) << 32) | ij.j,
        .spectral_count => |w| @as(u64, @bitCast(w)),
        .walsh => |s| s,
        .clifford_g2 => 0,
        .world_sum_mod => |p| p,
        .world_sign_mod => |p| p,
    };
}

pub fn openLedger() !void {
    if (!enabled or g_file != null) return;
    std.fs.cwd().makePath("/tmp/tier8-swarm") catch {};
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    g_file = file;
    const hdr = [_]u32{ MAGIC, VERSION, 0, 0 };
    try file.writeAll(std.mem.asBytes(&hdr));
}

pub fn closeLedger() void {
    if (g_file) |f| {
        f.close();
        g_file = null;
    }
}

pub fn resetLedger() void {
    g_seq = 0;
    g_n = 0;
    closeLedger();
}

fn appendRecord(rec: PromotionRecord) void {
    if (g_n < g_records.len) {
        g_records[g_n] = rec;
        g_n += 1;
    }
    if (g_file) |f| {
        f.writeAll(std.mem.asBytes(&rec)) catch {};
    }
}

pub fn recordPromote(
    cand: ui.Feature,
    cert_ok: bool,
    tax_survivor: bool,
    tax_basis_version: u32,
    remix_family: u8,
    test_acc: f64,
    cov_before: f64,
    cov_after: f64,
) void {
    if (!enabled) return;
    g_seq += 1;
    const rec = PromotionRecord{
        .seq = g_seq,
        .tax_basis_version = tax_basis_version,
        .feature_tag = featureTag(cand),
        .feature_param = featureParam(cand),
        .cert_ok = if (cert_ok) 1 else 0,
        .tax_survivor = if (tax_survivor) 1 else 0,
        .remix_family = remix_family,
        .test_acc_bits = f64ToBits(test_acc),
        .cov_before_bits = f64ToBits(cov_before),
        .cov_after_bits = f64ToBits(cov_after),
    };
    appendRecord(rec);
}

pub fn recordPromoteUnchecked(cand: ui.Feature, cert_ok: bool, cov_before: f64, cov_after: f64) void {
    if (!enabled) return;
    g_seq += 1;
    const rec = PromotionRecord{
        .seq = g_seq,
        .tax_basis_version = 0,
        .feature_tag = featureTag(cand),
        .feature_param = featureParam(cand),
        .cert_ok = if (cert_ok) 1 else 0,
        .tax_survivor = if (cert_ok) 1 else 0,
        .remix_family = 0,
        .test_acc_bits = 0,
        .cov_before_bits = f64ToBits(cov_before),
        .cov_after_bits = f64ToBits(cov_after),
    };
    appendRecord(rec);
}

pub const LedgerSummary = struct {
    total: usize,
    survivors: usize,
    blocked: usize,
};

pub fn summarize() LedgerSummary {
    var surv: usize = 0;
    for (g_records[0..g_n]) |r| {
        if (r.tax_survivor != 0) surv += 1;
    }
    return .{
        .total = g_n,
        .survivors = surv,
        .blocked = g_n - surv,
    };
}

pub fn recordCount() usize {
    return g_n;
}