const std = @import("std");
const expect = std.testing.expect;
const Allocator = std.mem.Allocator;

const Config = @import("Config.zig");
const Task = @import("task.zig").Task;
const Unit = @import("Unit.zig");
const util = @import("util.zig");
const Command = @import("task.zig").Command;

fn getLogLevel(allocator: Allocator) !util.LogLevel {
    const env_value = std.process.getEnvVarOwned(allocator, "LOG_LEVEL") catch |e|
        switch (e) {
        std.process.GetEnvVarOwnedError.EnvironmentVariableNotFound => "",
        else => return e,
    };
    defer allocator.free(env_value);
    return util.LogLevel.parse(env_value);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const global_logger =
        util.getLogger(
        std.io.getStdOut().writer(),
        // try getLogLevel(allocator),
        util.LogLevel.Debug,
        true,
        .{ .host = null, .collector = null },
    );

    {
        // just for debug info
        const cwd_path = try std.fs.cwd().realpathAlloc(allocator, ".");
        global_logger.dbg("Working directory: {s}", .{cwd_path});
        allocator.free(cwd_path);
    }

    global_logger.dbg("Loading hosts...", .{});
    const hosts = try getHosts();
    global_logger.dbg("Parsing arguments...", .{});
    var task = try Task.init(allocator, hosts);
    defer task.deinit();

    // TODO run check in one dir

    switch (task.cmd) {
        Command.Usage => {
            try printUsage(std.io.getStdOut().writer(), task.exe_name);
        },
        Command.Collect => {
            // TODO
        },
        Command.Check => {
            for (task.targets) |target| {
                const node = target.host;
                //const unit_path = target.path; // TODO
                const unit_path = ".";

                const logger = global_logger.withArgs(.{
                    .host = node,
                    .collector = unit_path,
                });

                logger.dbg("Checking dir: {s}", .{unit_path});

                // open unit
                var unit_dir = try std.fs.cwd().openDir(unit_path, .{ .iterate = true });
                defer unit_dir.close();
                var unit = try Unit.open(unit_dir, allocator);
                defer unit.deinit();

                // filter
                var filters = try unit.iterateFilters();
                while (try filters.next()) |filter_filename| {
                    logger.dbg("Using filter: {s}", .{filter_filename});
                    // todo filter
                }
            }
        },
    }
}

fn printUsage(out: anytype, program_name: ?[]const u8) !void {
    try out.print(
        "usage: {s} collect|check",
        .{program_name orelse "<program>"},
    );
}

// TODO(2): hardcoded for now
fn getHosts() ![]const []const u8 {
    const hosts = ([_][]const u8{
        "a",
        "b",
        "c",
    })[0..];
    return hosts;
}
