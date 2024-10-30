const Unit = @This();

dir: Dir,
allocator: Allocator,
fifo: FifoType,
path_buf: [fs.MAX_NAME_BYTES]u8,
extension: []const u8,
artifacts_dir: Dir,

pub fn open(dir: Dir, allocator: Allocator) !Unit {
    var path_buf: [fs.MAX_NAME_BYTES]u8 = undefined;

    const extension: []const u8 = blk: {
        const path = try dir.realpath(".", &path_buf);
        var it = std.mem.splitBackwardsScalar(u8, path, '.');
        break :blk it.next().?;
    };

    const artifacts_dir = try dir.openDir(Config.DIRNAME_ARTIFACTS, .{});

    return Unit{
        .dir = dir,
        .allocator = allocator,
        .fifo = FifoType.init(),
        .path_buf = path_buf,
        .extension = extension,
        .artifacts_dir = artifacts_dir,
    };
}

pub fn deinit(self: *Unit) void {
    self.artifacts_dir.close();
    self.fifo.deinit();
}

pub fn iterateFilters(self: Unit) !Filter.Iterator {
    return try Filter.Iterator.init(self.dir);
}

pub inline fn artifactFileTask(self: Unit, target: []const u8) FileTask {
    var file_name_buf: [std.fs.MAX_NAME_BYTES]u8 = undefined;
    const file_name =
        std.fmt.bufPrint(
        &file_name_buf,
        Config.FILENAME_ARTIFACT_FMT,
        .{ target, self.extension },
    ) catch |e| {
        switch (e) {
            std.fmt.BufPrintError.NoSpaceLeft => {
                @panic("buffer overflow");
            },
        }
    };
    return FileTask.init(self.allocator, file_name, self.artifacts_dir);
}

pub inline fn benchmarkFileTask(self: Unit) FileTask {
    var file_name_buf: [std.fs.MAX_NAME_BYTES]u8 = undefined;
    const file_name =
        std.fmt.bufPrint(
        &file_name_buf,
        Config.FILENAME_BENCHMARK_FMT,
        .{self.extension},
    ) catch |e| {
        switch (e) {
            std.fmt.BufPrintError.NoSpaceLeft => {
                @panic("buffer overflow");
            },
        }
    };
    return FileTask.init(self.allocator, file_name, self.dir);
}

/// here be some dragons
pub const Filter = struct {
    file_name: [std.fs.MAX_NAME_BYTES:0]u8,
    exec_path: [std.fs.MAX_NAME_BYTES:0]u8,

    // Find filters in a given directory.
    pub const Iterator = struct {
        inner: Dir.Iterator,
        dir: Dir,
        pub fn init(dir: Dir) !Iterator {
            const inner = dir.iterate();
            return Iterator{
                .dir = dir,
                .inner = inner,
            };
        }
        pub fn next(self: *Iterator) !?Filter {
            while (try self.inner.next()) |entry| {
                if (self.match(entry)) {
                    var name: [std.fs.MAX_NAME_BYTES:0]u8 = undefined;
                    var exec_path: [std.fs.MAX_NAME_BYTES:0]u8 = undefined;
                    // TODO(2): only works for .
                    _ = std.fmt.bufPrintZ(&exec_path, "./{s}", .{entry.name}) catch |e| switch (e) {
                        std.fmt.BufPrintError.NoSpaceLeft => {
                            @panic("buffer overflow");
                        },
                    };
                    _ = std.fmt.bufPrintZ(&name, "{s}", .{entry.name}) catch |e| switch (e) {
                        std.fmt.BufPrintError.NoSpaceLeft => {
                            @panic("buffer overflow");
                        },
                    };
                    return Filter{
                        .exec_path = exec_path,
                        .file_name = name,
                    };
                }
            }
            return null;
        }
        inline fn match(_: Iterator, entry: Dir.Entry) bool {
            return entry.kind == File.Kind.file and
                std.mem.startsWith(u8, entry.name, Config.FILENAME_FILTER_PREFIX) and
                std.mem.endsWith(u8, entry.name, Config.FILENAME_FILTER_SUFIX);
        }
        test "filter file matcher" {
            try expect(!match(undefined, Dir.Entry{
                .kind = File.Kind.file,
                .name = Config.FILENAME_FILTER_PREFIX ++ "abc",
            }));
            try expect(!match(undefined, Dir.Entry{
                .kind = File.Kind.file,
                .name = "abc" ++ Config.FILENAME_FILTER_SUFIX,
            }));
            try expect(!match(undefined, Dir.Entry{
                .kind = File.Kind.directory,
                .name = Config.FILENAME_FILTER_PREFIX ++ "abc" ++ Config.FILENAME_FILTER_SUFIX,
            }));
            try expect(match(undefined, Dir.Entry{
                .kind = File.Kind.file,
                .name = Config.FILENAME_FILTER_PREFIX ++ "abc" ++ Config.FILENAME_FILTER_SUFIX,
            }));
        }
    };
};

pub const FileTask = struct {
    file_name: [std.fs.MAX_NAME_BYTES:0]u8,
    dir: Dir,
    content: ?[]u8,
    inner: struct {
        allocator: Allocator,
    },

    pub fn init(
        allocator: Allocator,
        file_name: []const u8,
        dir: Dir,
    ) FileTask {
        var t: FileTask = .{
            .file_name = undefined,
            .dir = dir,
            .content = null,
            .inner = .{ .allocator = allocator },
        };
        _ = std.fmt.bufPrintZ(&t.file_name, "{s}", .{file_name}) catch |e| {
            switch (e) {
                std.fmt.BufPrintError.NoSpaceLeft => {
                    @panic("buffer overflow");
                },
            }
        };
        return t;
    }

    pub fn deinit(self: *FileTask) void {
        if (null != self.content)
            self.inner.allocator.free(self.content);
    }

    /// Content is owned by the struct
    pub fn load(self: *FileTask) !void {
        const file = try self.dir.openFileZ(&self.file_name, .{});
        defer file.close();
        const reader = file.reader();
        self.content = try reader.readAllAlloc(self.inner.allocator, Config.MAX_FILE_SIZE);
    }

    pub fn filterWith(self: *FileTask, filter: Filter, target: []const u8) !void {
        var argvtest: [2][]const u8 = undefined;
        argvtest[0] = filter.exec_path[0..];
        argvtest[1] = target;

        var filter_process = std.process.Child.init(
            &argvtest,
            self.inner.allocator,
        );
        filter_process.stdin_behavior = .Pipe;
        filter_process.stdout_behavior = .Pipe;
        try filter_process.spawn();

        assert(null != self.content);
        assert(null != filter_process.stdin);
        assert(null != filter_process.stdout);

        try filter_process.stdin.?.writeAll(self.content.?);
        filter_process.stdin.?.close();

        // TODO(2): waiting doesn't work?
        // const exit_code = try filter_process.wait();
        // _ = exit_code;

        const new_buf = try filter_process.stdout.?.readToEndAlloc(
            self.inner.allocator,
            Config.MAX_FILE_SIZE,
        );

        // replace content
        self.inner.allocator.free(self.content.?);
        self.content = new_buf;
    }
};

const std = @import("std");
const fs = std.fs;
const expect = std.testing.expect;
const assert = std.debug.assert;
const File = std.fs.File;
const Dir = std.fs.Dir;
const Allocator = std.mem.Allocator;

const Logger = @import("Logger.zig");
const Config = @import("Config.zig");

// tests won't run unless they're referenced
test {
    std.testing.refAllDecls(@This());
}

// TODO(3) The type `FifoType` shouldn't be needed, i think...
//
// This doesn't work:
//   @Type(@field(Unit, "fifo")).init()
//
// So I use this:
//   FifoType.init()
const FifoType = std.fifo.LinearFifo(u8, .{ .Static = Config.FIFO_BUF_SIZE });
