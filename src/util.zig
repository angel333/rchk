const std = @import("std");
const trait = std.meta.trait;
const expect = std.testing.expect;

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
        .{ "debug", LogLevel.Verbose },
    });
    pub fn parse(text: []const u8) LogLevel {
        return lut.get(text) orelse LogLevel.Default;
    }
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

// oh my.. this doesn't feel right at all :/
const Writer = @TypeOf(std.io.getStdOut().writer());

pub fn getLogger(
    out_stream: anytype,
    verbosity_level: LogLevel,
    enable_colors: bool,
    args: Logger.Component,
) Logger {
    const palette = if (enable_colors) PALETTE_COLORS else PALETTE_BW;
    return Logger{
        .out_stream = out_stream,
        .verbosity_level = verbosity_level,
        .palette = palette,
        .component = args,
    };
}

pub const Logger = struct {
    out_stream: Writer,
    palette: AnsiPalette,
    verbosity_level: LogLevel,
    component: Component,

    const Component = struct {
        host: ?[]const u8,
        collector: ?[]const u8,
    };

    /// makes a copy with different args
    pub fn withArgs(self: Logger, component: Component) Logger {
        return Logger{
            .out_stream = self.out_stream,
            .palette = self.palette,
            .verbosity_level = self.verbosity_level,
            .component = component,
        };
    }

    /// custom print function that panics on any error
    fn print(self: Logger, comptime format: []const u8, args: anytype) void {
        self.out_stream.print(format, args) catch {
            std.debug.panic("FATAL: Irrecoverable logging error!", .{});
        };
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

    /// shortcut
    pub fn dbg(self: Logger, comptime format: []const u8, args: anytype) void {
        self.msg(format, args, Kind.Debug, LogLevel.Debug);
    }
    pub fn info(self: Logger, comptime format: []const u8, args: anytype) void {
        self.msg(format, args, Kind.Info, LogLevel.Verbose);
    }
    pub fn ok(self: Logger, comptime format: []const u8, args: anytype) void {
        self.msg(format, args, Kind.Ok, LogLevel.Default);
    }
    pub fn fail(self: Logger, comptime format: []const u8, args: anytype) void {
        self.msg(format, args, Kind.Failure, LogLevel.Warn);
    }
    pub fn todo(self: Logger, comptime format: []const u8, args: anytype) void {
        self.msg(format, args, Kind.Todo, LogLevel.Warn);
    }
    pub fn skip(self: Logger, comptime format: []const u8, args: anytype) void {
        self.msg(format, args, Kind.Skip, LogLevel.Warn);
    }
};

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
