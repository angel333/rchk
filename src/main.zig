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
                logger.dbg("Checking dir: {s}", .{unit_path});
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

inline fn loadFileTask(task: *Unit.FileTask, logger: Logger) !void {
    logger.debug("Loading file: {s}", .{task.file_name});
    task.load() catch |e| switch (e) {
        //std.fs.File.ReadError.AccessDenied
        std.fs.File.OpenError.FileNotFound => {
            logger.fail("File not found: {s}", .{task.file_name});
            return;
        },
        else => {
            logger.fail("Couldn't load file: {s}", .{task.file_name});
            return e;
        },
    };
}

fn checkUnit(
    allocator: Allocator,
    unit_path: []const u8,
    target: []const u8,
    logger: Logger,
) !void {
    var unit_dir = try std.fs.cwd().openDir(unit_path, .{ .iterate = true });
    defer unit_dir.close();
    var unit = try Unit.open(unit_dir, allocator);
    defer unit.deinit();

    var benchmark = unit.benchmarkFileTask();
    var artifact = unit.artifactFileTask(target);

    try loadFileTask(&benchmark, logger);
    try loadFileTask(&artifact, logger);

    if (!std.mem.eql(u8, benchmark.content.?, artifact.content.?)) {
        logger.fail("Artifact doesn't match!", .{});
    } else {
        logger.ok("Artifact matches.", .{});
    }
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
