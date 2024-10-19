//! I wasn't aware there was `std.log` so I wrote this. Gonna leave it here for
//! now, but maybe let's stay fairly close to `std.log` interfaces so that
//! when/if I want to switch to it, I can do so easily.

out_stream: Writer,
palette: AnsiPalette,
verbosity_level: LogLevel,
component: Component,

const Writer = @TypeOf(std.io.getStdOut().writer());

pub const debug = aliasFn(Kind.Debug, LogLevel.Debug);
pub const dbg = Logger.debug;
pub const info = aliasFn(Kind.Info, LogLevel.Verbose);
pub const ok = aliasFn(Kind.Ok, LogLevel.Default);
pub const fail = aliasFn(Kind.Failure, LogLevel.Warn);
pub const todo = aliasFn(Kind.Todo, LogLevel.Warn);
pub const skip = aliasFn(Kind.Skip, LogLevel.Warn);

pub fn init(
    out_stream: Writer,
    verbosity_level: LogLevel,
    enable_colors: bool,
) Logger {
    const palette = if (enable_colors) PALETTE_COLORS else PALETTE_BW;
    return Logger{
        .out_stream = out_stream,
        .verbosity_level = verbosity_level,
        .palette = palette,
        .component = .{ .host = null, .collector = null },
    };
}

/// makes a copy with different args
pub fn scoped(self: Logger, component: Component) Logger {
    var new_logger = self; // will copy, since self is not a pointer
    new_logger.component = component;
    return new_logger;
}

const Component = struct {
    host: ?[]const u8,
    collector: ?[]const u8,
};

/// custom print function that panics on any error
fn print(self: Logger, comptime format: []const u8, args: anytype) void {
    self.out_stream.print(format, args) catch {
        @panic("irrecoverable logging error");
    };
}

pub fn msg(
    self: Logger,
    comptime format: []const u8,
    args: anytype,
    comptime kind: Kind,
    comptime level: LogLevel,
) void {
    if (@intFromEnum(level) > @intFromEnum(self.verbosity_level)) return;

    // leading part of the log message - [  OK  ], [ FAIL ], etc.
    self.print("{s}[{s: ^6}] ", .{
        kind.getColor(self.palette),
        kind.getText(),
    });

    self.writeLoggerHostPart(
        self.component.host,
        self.component.collector,
        self.palette,
    );

    self.print("{s}", .{self.palette.reset});

    // the actual message
    self.print(format, args);
    self.print("\n", .{});
}

fn aliasFn(kind: Kind, min_level: LogLevel) fn (Logger, comptime []const u8, anytype) void {
    return struct {
        pub fn call(ctx: Logger, comptime format: []const u8, args: anytype) void {
            ctx.msg(format, args, kind, min_level);
        }
    }.call;
}

/// [host:collector] (w/ trailing space)
inline fn writeLoggerHostPart(
    self: Logger,
    component: ?[]const u8,
    subcomponent: ?[]const u8,
    palette: AnsiPalette,
) void {
    if (null == component and null == subcomponent) return;

    // [
    self.print("{s}[", .{palette.blue});

    // component
    if (null != component) {
        self.print("{s}{s}{s}", .{
            palette.yellow, component.?, palette.blue,
        });
    }

    // :subcomponent
    if (null != subcomponent) {
        self.print(":{s}", .{subcomponent.?});
    }

    // ]
    self.print("] ", .{});
}

const Kind = enum {
    Debug,
    Info,
    Ok,
    Failure,
    Todo,
    Skip,
    fn getColor(comptime self: Kind, palette: AnsiPalette) []const u8 {
        return switch (self) {
            Kind.Debug => palette.white,
            Kind.Info => palette.blue,
            Kind.Ok => palette.green,
            Kind.Failure => palette.red,
            Kind.Todo => palette.yellow,
            Kind.Skip => palette.yellow,
        };
    }
    fn getText(comptime self: Kind) []const u8 {
        return switch (self) {
            Kind.Debug => "DEBUG",
            Kind.Info => "INFO",
            Kind.Ok => "OK",
            Kind.Failure => "FAIL",
            Kind.Todo => "TODO",
            Kind.Skip => "SKIP",
        };
    }
};

pub const LogLevel = enum(i8) {
    Quiet = -1,
    Warn = 0,
    Default = 1,
    Verbose = 2,
    Debug = 3,
    const default = LogLevel.Default; // duh
    const lut = std.StaticStringMapWithEql(LogLevel, std.ascii.eqlIgnoreCase).initComptime(.{
        .{ "quiet", LogLevel.Quiet },
        .{ "warn", LogLevel.Warn },
        .{ "", LogLevel.Default },
        .{ "verbose", LogLevel.Verbose },
        .{ "debug", LogLevel.Debug },
    });
    pub fn parse(text: []const u8) LogLevel {
        return lut.get(text) orelse LogLevel.Default;
    }
};

const AnsiPalette = struct {
    red: []const u8,
    green: []const u8,
    yellow: []const u8,
    blue: []const u8,
    purple: []const u8,
    cyan: []const u8,
    white: []const u8,
    reset: []const u8,
};

const PALETTE_COLORS = AnsiPalette{
    .red = "\x1b[31m",
    .green = "\x1b[32m",
    .yellow = "\x1b[33m",
    .blue = "\x1b[34m",
    .purple = "\x1b[35m",
    .cyan = "\x1b[36m",
    .white = "\x1b[37m",
    .reset = "\x1b[0m",
};

const PALETTE_BW = AnsiPalette{
    .red = "",
    .green = "",
    .yellow = "",
    .blue = "",
    .purple = "",
    .cyan = "",
    .white = "",
    .reset = "",
};

const Logger = @This();

const std = @import("std");
