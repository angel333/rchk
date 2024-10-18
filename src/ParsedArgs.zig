exe_name: []const u8 = "rchk",
cmd: Command,
units: []const []const u8,
targets: []const []const u8,
inner: struct {
    arena: std.heap.ArenaAllocator,
},

const MAX_MULTI_VALUES = 128;

pub fn init(allocator: Allocator) !ParsedArgs {
    var arena = std.heap.ArenaAllocator.init(allocator);

    var app = yazap.App.init(
        arena.allocator(),
        "rchk",
        "remote node checker",
    );

    var root = app.rootCommand();
    root.setProperty(.help_on_empty_args);
    root.setProperty(.subcommand_required);

    try root.addArg(Arg.multiValuesOption("targets", 't', "Remote nodes (defaults to all configured targets)", MAX_MULTI_VALUES));
    try root.addArg(Arg.multiValuesOption("units", 'u', "Directories to run (defaults to '.').", MAX_MULTI_VALUES));

    var cmd_collect = app.createCommand(
        "collect",
        "Collect reports.",
    );

    var cmd_check = app.createCommand(
        "check",
        "Check the reports.",
    );

    _ = .{ &cmd_collect, &cmd_check };

    try root.addSubcommands(&[_]yazap.Command{
        cmd_collect,
        cmd_check,
    });

    const matches = try app.parseProcess();

    const cmd = blk: {
        if (null != matches.subcommandMatches("collect"))
            break :blk Command.Collect;
        if (null != matches.subcommandMatches("check"))
            break :blk Command.Check;
        unreachable;
    };

    return ParsedArgs{
        .cmd = cmd,
        .targets = argValsOwned(arena.allocator(), matches, "targets"),
        .units = argValsOwned(arena.allocator(), matches, "units"),
        .inner = .{
            .arena = arena,
        },
    };
}

pub fn deinit(self: ParsedArgs) void {
    defer self.inner.arena.deinit();
}

pub const Command = enum {
    Collect,
    Check,
};

const ParsedArgs = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const yazap = @import("yazap");
const Arg = yazap.Arg;

/// Reliably return an array of argument values
///
/// Motivation:
/// The yzaps library's original `ArgMatches.getMultiValues()` and
/// `ArgMatches.getSingleValue()` don't obbey the argument definitions. They
/// seem to rely on the actual arguments provided instead. If only one value is
/// provided, `ArgMatches.getMultiValues()` will return null and
/// `ArgMatches.getSingleValue()` will return the one value. Vice versa, with
/// multiple provided values, `getSingleValue` will not work. This function
/// therefore tries out both functions.
///
/// Additionally, new memory is allocated (yzap apparently reuses it).
///
/// Instead of null, this function will always return an array, even if empty.
pub fn argValsOwned(
    allocator: Allocator,
    matches: yazap.ArgMatches,
    name: []const u8,
) []const []const u8 {
    const slice = blk: {
        if (matches.getSingleValue(name)) |value|
            break :blk &.{value};
        if (matches.getMultiValues(name)) |values|
            break :blk values;
        return &[0][]const u8{}; // no values
    };
    const owned = allocator.dupe([]const u8, slice) catch
        @panic("allocation error");
    return owned;
}
