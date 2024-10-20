const std = @import("std");
const expect = std.testing.expect;
const Allocator = std.mem.Allocator;

const Config = @import("Config.zig");
const ParsedArgs = @import("ParsedArgs.zig");
const Command = ParsedArgs.Command;
const Unit = @import("Unit.zig");
const Logger = @import("Logger.zig");
const LogLevel = Logger.LogLevel;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var args = try ParsedArgs.init(allocator);
    defer args.deinit();

    const logger = Logger.init(
        std.io.getStdOut().writer(),
        getLogLevel(),
        true,
    );
    logger.debug("hello", .{});

    printInitialDebugInfo(logger, args);

    const defUnits: []const []const u8 = &.{"."};

    // fill hosts with configuration
    const targets = if (0 != args.targets.len) args.targets else try getHosts();
    const units = if (0 != args.units.len) args.units else defUnits;

    switch (args.cmd) {
        Command.Collect => {
            @panic("not implemented");
        },
        Command.Check => {
            for (units) |unit_path| {
                for (targets) |target| {
                    try checkUnit(allocator, unit_path, target, logger.scoped(.{
                        .host = target,
                        .collector = unit_path,
                    }));
                }
            }
        },
    }
}

fn checkUnit(
    allocator: Allocator,
    unit_path: []const u8,
    target: []const u8,
    logger: Logger,
) !void {
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
    _ = target;
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

fn getLogLevel() Logger.LogLevel {
    var buf: [0x20]u8 = undefined; // enough for one word
    const GetEnvVarOwnedError = std.process.GetEnvVarOwnedError;
    var buf_allocator = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = buf_allocator.allocator();
    // no deinit or free with fixed buffer
    const env_value = std.process.getEnvVarOwned(allocator, "LOG_LEVEL") catch |e|
        switch (e) {
        GetEnvVarOwnedError.OutOfMemory,
        GetEnvVarOwnedError.EnvironmentVariableNotFound,
        => "",
        GetEnvVarOwnedError.InvalidWtf8 => @panic("env var encoding error"),
    };
    return Logger.LogLevel.parse(env_value);
}

inline fn printInitialDebugInfo(global_logger: Logger, args: ParsedArgs) void {
    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const cwd_path = std.fs.cwd().realpath(".", &buf) catch {
        @panic("cannot resolve working directory");
    };
    global_logger.dbg("Working directory: {s}", .{cwd_path});
    global_logger.dbg("Number of units: {d}", .{args.units.len});
    global_logger.dbg("Units from args ({d}): {s}", .{ args.units.len, args.units });
    global_logger.dbg("Targets from args ({d}): {s}", .{ args.targets.len, args.targets });
}
