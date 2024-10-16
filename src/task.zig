const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Target = struct {
    type: TargetType,
    host: []const u8,
    path: []const u8,

    const TargetType = enum { Collect, Check };
};

pub const Task = struct {
    /// current name of the program
    exe_name: []const u8,

    /// which operation to run
    cmd: Command,

    /// files to be processed
    targets: []const Target,

    inner: struct {
        arena: std.heap.ArenaAllocator,
    },

    pub fn init(allocator: Allocator, hosts: []const []const u8) !Task {
        var args = try std.process.argsWithAllocator(allocator);
        defer args.deinit();

        var arena = std.heap.ArenaAllocator.init(allocator);
        const arena_allocator = arena.allocator();

        const exe_path = args.next() orelse "";
        const exe_name = try arena_allocator.dupe(
            u8,
            std.fs.path.basename(exe_path),
        );

        const cmd = Command.parse(args.next() orelse "");

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

        return Task{
            .inner = .{
                .arena = arena,
            },
            .cmd = cmd,
            .exe_name = exe_name,
            .targets = targets,
        };
    }

    pub fn deinit(self: *Task) void {
        self.inner.arena.deinit();
    }
};

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
    inline fn parse(cmd: []const u8) Command {
        const map = comptime std.StaticStringMap(Command).initComptime(
            Command.parser_lut,
        );
        return map.get(cmd) orelse Command.Usage;
    }
};

test "parse commands" {
    try std.testing.expectEqual(Command.Usage, Command.parse(""));
    try std.testing.expectEqual(Command.Check, Command.parse("check"));
}
