//! A total type checker for the base system (STLC + Unit/Bool/Pair).
//!
//! It maps an untyped `RawTerm` to an intrinsically-typed `Term`, or fails. It
//! is decidable and total: recursion is structural on the raw term, and the
//! object language has no general recursion, so checking always terminates.
//! W-type rules (`WIntro`/`WRec`) are intentionally NOT checked here — those
//! terms are built by the sleep phase as templates after a W-type is invented,
//! and full dependent checking of them is post-milestone work (Section 11).

const std = @import("std");
const types = @import("types.zig");
const terms = @import("terms.zig");
const library = @import("library.zig");
const Type = types.Type;
const Term = terms.Term;
const Library = library.Library;

pub const RawTag = enum {
    Var,
    Lam,
    App,
    UnitIntro,
    BoolIntro,
    Pair,
    Proj1,
    Proj2,
};

pub const RawTerm = struct {
    tag: RawTag,
    idx: usize = 0, // Var
    boolVal: bool = false, // BoolIntro
    dom: ?*Type = null, // Lam domain annotation (required to synthesize a Lam)
    a: ?*const RawTerm = null,
    b: ?*const RawTerm = null,
};

pub const CheckError = error{
    TypeMismatch,
    NotAFunction,
    NotAPair,
    UnboundVar,
    NeedsAnnotation,
    OutOfMemory,
};

/// Synthesize the type of `raw` under `ctx` (de Bruijn: index 0 is the most
/// recently bound variable, i.e. the last element of `ctx`).
pub fn infer(lib: *const Library, ctx: []const *Type, raw: *const RawTerm) CheckError!*Term {
    const a = lib.a;
    switch (raw.tag) {
        .Var => {
            if (raw.idx >= ctx.len) return CheckError.UnboundVar;
            const ty = ctx[ctx.len - 1 - raw.idx];
            return Term.vr(a, raw.idx, ty);
        },
        .UnitIntro => return Term.unitIntro(a, lib.unit),
        .BoolIntro => return Term.boolIntro(a, raw.boolVal, lib.bool_),
        .Lam => {
            const dom = raw.dom orelse return CheckError.NeedsAnnotation;
            const body_raw = raw.a orelse return CheckError.NeedsAnnotation;
            const extended = try a.alloc(*Type, ctx.len + 1);
            @memcpy(extended[0..ctx.len], ctx);
            extended[ctx.len] = dom;
            const body = try infer(lib, extended, body_raw);
            const fun_ty = try Type.mkFun(a, dom, body.ty.?);
            return Term.lam(a, body, fun_ty);
        },
        .App => {
            const func_raw = raw.a orelse return CheckError.NeedsAnnotation;
            const arg_raw = raw.b orelse return CheckError.NeedsAnnotation;
            const func = try infer(lib, ctx, func_raw);
            const fty = func.ty.?;
            if (fty.tag != .Fun) return CheckError.NotAFunction;
            const arg = try infer(lib, ctx, arg_raw);
            if (!Type.eql(arg.ty.?, fty.dom.?)) return CheckError.TypeMismatch;
            return Term.app(a, func, arg, fty.cod.?);
        },
        .Pair => {
            const left_raw = raw.a orelse return CheckError.NeedsAnnotation;
            const right_raw = raw.b orelse return CheckError.NeedsAnnotation;
            const left = try infer(lib, ctx, left_raw);
            const right = try infer(lib, ctx, right_raw);
            const pty = try Type.mkPair(a, left.ty.?, right.ty.?);
            return Term.pair(a, left, right, pty);
        },
        .Proj1 => {
            const tgt_raw = raw.a orelse return CheckError.NeedsAnnotation;
            const tgt = try infer(lib, ctx, tgt_raw);
            if (tgt.ty.?.tag != .Pair) return CheckError.NotAPair;
            return Term.proj1(a, tgt, tgt.ty.?.dom.?);
        },
        .Proj2 => {
            const tgt_raw = raw.a orelse return CheckError.NeedsAnnotation;
            const tgt = try infer(lib, ctx, tgt_raw);
            if (tgt.ty.?.tag != .Pair) return CheckError.NotAPair;
            return Term.proj2(a, tgt, tgt.ty.?.cod.?);
        },
    }
}

/// Check `raw` against `expected`, returning the typed term on success.
pub fn check(lib: *const Library, ctx: []const *Type, raw: *const RawTerm, expected: *Type) CheckError!*Term {
    const t = try infer(lib, ctx, raw);
    if (!Type.eql(t.ty.?, expected)) return CheckError.TypeMismatch;
    return t;
}

test "identity type-checks to Unit -> Unit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = try Library.init(a);
    defer lib.deinit();

    const body = RawTerm{ .tag = .Var, .idx = 0 };
    const id = RawTerm{ .tag = .Lam, .dom = lib.unit, .a = &body };
    const expected = try Type.mkFun(a, lib.unit, lib.unit);
    const t = try check(&lib, &.{}, &id, expected);
    try std.testing.expectEqual(terms.TermTag.Lam, t.tag);
    try std.testing.expect(Type.eql(t.ty.?, expected));
}

test "applying identity to unit checks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = try Library.init(a);
    defer lib.deinit();

    const body = RawTerm{ .tag = .Var, .idx = 0 };
    const id = RawTerm{ .tag = .Lam, .dom = lib.unit, .a = &body };
    const u = RawTerm{ .tag = .UnitIntro };
    const applied = RawTerm{ .tag = .App, .a = &id, .b = &u };
    const t = try infer(&lib, &.{}, &applied);
    try std.testing.expect(Type.eql(t.ty.?, lib.unit));
}

test "ill-typed application is rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = try Library.init(a);
    defer lib.deinit();

    // applying a Unit value as if it were a function
    const u = RawTerm{ .tag = .UnitIntro };
    const bad = RawTerm{ .tag = .App, .a = &u, .b = &u };
    try std.testing.expectError(CheckError.NotAFunction, infer(&lib, &.{}, &bad));
}
