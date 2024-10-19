const yazap = @import("yazap");

/// current name of the executable
exe_name: ?[]const u8,

/// which operation to run
cmd: ?Command,

targets: []const u8,

units: UnitsIterator,

inner: struct {
    arena: std.heap.ArenaAllocator,
},
const UnitsIterator = mem.TokenIterator(u8, .scalar);

pub fn iterateUnits(self: ParsedArgs) UnitsIterator {
    return mem.tokenizeScalar(u8, self.units_slice, ',');
}

pub fn parse(allocator: Allocator) !ParsedArgs {
    var arena = std.heap.ArenaAllocator.init(allocator);

    var args = try std.process.argsWithAllocator(arena.allocator());
    var target_list = std.ArrayList([]const u8).init(arena.allocator());
    var units_list = std.ArrayList([]const u8).init(arena.allocator());

    // var exe_name: ?[]const u8 = null;
    const exe_name = parseExeName(args.next(), args);

    var units: ?[]const u8 = null;

    var units_val = "";

    // order is important here
    var param: []const u8 = "";
    var val: []const u8 = "";
    while (args.next()) |cur| {
        // --param[=<value>]
        if (std.mem.startsWith(u8, cur, "--")) {
            val = blk: {
                const eq_pos = std.mem.indexOfScalar(u8, cur, '=');
                if (null != eq_pos) {
                    break :blk cur[(eq_pos + 1)..];
                }
            };
            if (null != std.mem.indexOfScalar(u8, cur, '=')) {}
            val =
                //
                continue;
        }
        // -x
        if (std.mem.startsWith(u8, cur, "-")) {
            val = args.next();
            //
            continue;
        }

        units_slice = parseUnits(args.next(), args, &units_list) orelse "";

        //if (null == exe_name)
    }

    // global parameters

    const cmd = Command.parse(args.next());

    while (args.next()) |cur| {
        target_list.append(cur) catch std.debug.panic("allocation failed", .{});
    }

    return ParsedArgs{
        .exe_name = exe_name,
        .cmd = cmd,
        .units_slice = units_slice,
        .targets = target_list.items,
        .inner = .{
            .arena = arena,
        },
    };
}

pub fn deinit(self: ParsedArgs) void {
    self.inner.arena.deinit();
}

inline fn parseExeName(cur: ?[]const u8, _: *ArgsIterator) ?[]const u8 {
    const exe_path = cur;
    if (null == exe_path) return null;
    return std.fs.path.basename(exe_path);
}

// side effect: might iterate the iterator once
inline fn parseUnits(
    cur: ?[]const u8,
    it: *ArgsIterator,
) ?[]const u8 {
    if (mem.startsWith(u8, cur, "--units="))
        return cur[(comptime "--units".len)..];
    if (mem.eql(u8, cur, "-u"))
        return it.next() orelse "";
    return null;
}

pub const Command = enum {
    Usage,
    Collect,
    Check,
    const parser_lut = .{
        .{ "collect", Command.Collect },
        .{ "check", Command.Check },
        .{ "pull", Command.Collect },
        .{ "usage", Command.Usage },
        .{ "", Command.Usage },
    };
    inline fn parse(cmd: ?[]const u8) ?Command {
        const map = comptime std.StaticStringMap(Command).initComptime(
            Command.parser_lut,
        );
        return map.get(cmd);
    }
};

const ParsedArgs = @This();

const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const ArgsIterator = std.process.ArgsIterator;

// ---
// ---
// ---
// ---
// ---
// ---
// ---
// ---
// ---
// ---
// ---

pub const Target = struct {
    type: TargetType,
    host: []const u8,
    path: []const u8,

    const TargetType = enum { Collect, Check };
};

pub const Task = struct {
    /// files to be processed
    targets: []const Target,

    pub fn init(allocator: Allocator, hosts: []const []const u8) !Task {

        // collect the rest and populate targets with it
        var targets_list = std.ArrayList(Target).init(allocator);
        defer targets_list.deinit();

        while (args.next()) |path| {
            for (hosts) |host| {
                const pathAl = try arena_allocator.dupe(u8, path);
                try targets_list.append(Target{
                    .type = Target.TargetType.Collect,
                    .host = host,
                    .path = pathAl,
                });
            }
        }

        const targets = try arena_allocator.dupe(Target, targets_list.items);
    }

    pub fn deinit(self: *Task) void {
        self.inner.arena.deinit();
    }
};

test "parse commands" {
    try std.testing.expectEqual(Command.Usage, Command.parse(""));
    try std.testing.expectEqual(Command.Check, Command.parse("check"));
}
