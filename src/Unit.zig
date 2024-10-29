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

pub const Filter = struct {
    name: []const u8,

    pub fn run(self: Filter, reader: anytype, writer: anytype) !void {
        _ = self;
        _ = reader;
        _ = writer;
        // TODO run it
        unreachable;
    }

    // Find filters in a given directory.
    pub const Iterator = struct {
        inner: Dir.Iterator,
        pub fn init(dir: Dir) !Iterator {
            const inner = dir.iterate();
            return Iterator{
                .inner = inner,
            };
        }
        pub fn next(self: *Iterator) !?[]const u8 {
            while (try self.inner.next()) |entry| {
                if (self.match(entry)) {
                    // TODO(3): Perhaps we could pass fn instead.
                    return entry.name;
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
};

const std = @import("std");
const fs = std.fs;
const expect = std.testing.expect;
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
