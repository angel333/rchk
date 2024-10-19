/// Iterator for filter names in a given directory.


pub const TextFilter = struct {
    fifo: FifoType,
    pub fn run(self: *TextFilter, reader: anytype, writer: anytype) !void {
        self.fifo.pump(reader, writer);
    }
    pub fn init() TextFilter {
        return TextFilter{
            .fifo = FifoType.init(),
        };
    }
    pub fn deinit(self: TextFilter) void {
        self.fifo.deinit();
    }
};

pub const Unit = struct {

    pub fn iterateFilters(self: Unit) !FilterFileNameIterator {
        return FilterFileNameIterator.init(self.dir);
    }

    /// Runs a single filter on a report.
    pub fn filter(self: *Unit, node: []const u8, via: TextFilter) !void {
        _ = via;
        _ = node;
        _ = self;

        // TODO find node report
        //

    }

    //pub fn getFiltersFilenames(self: Unit) !File {}

    // TODO WE DONT NEED TO SAVE ARTIFACTS NOW.. Just raw...

    pub fn open_raw_artifact(self: Unit, node: []const u8) !File {
        self.allocator.alloc(u8, node.len + 4);
        const artifacts_dir = try self.dir.openDir(config.DIRNAME_ARTIFACTS, .{});
        return artifacts_dir.openFile("", .{ .mode = File.OpenMode.write_only });
    }

    // this needs to be granual b/c logging

    // collector_exe: std.fs.File,
    // filter_exe: std.fs.File,
    // reports_dir: std.fs.Dir,
    // artifacts_dir: std.fs.Dir,

    //fn filter() {}

    /// finds the raw report (artifact)
    /// finds the filter(s)
    /// filters raw artifact, saves as artifact
    /// last artifact is saved as report
    /// compare report to benchmark
    /// compares to benchmark
    pub fn check(self: *Unit, node: []const u8) !bool {
        _ = node;
        // const raw_artifact = try self;

        // const report_file = self.openNodeReport(node);
        // const filters = self.findFilters();
        // for (filters) |current_filter| {
        //     current_filter(report_file.reader(), artifact_writer(""));
        // }

        const stdin_file = try self.dir.openFile("testreport.txt", .{});
        defer stdin_file.close();

        filter();
        // var filter = std.process.Child.init(&.{CMD_FILTER}, self.allocator);
        // filter.stdin_behavior = .Pipe;
        // filter.stdout_behavior = .Pipe;

        // try filter.spawn();

        try self.fifo.pump(stdin_file, filter.stdin.?);
        filter.stdin.?.close();

        try self.fifo.pump(filter.stdout.?, std.io.getStdOut());

        return true;
    }
};

pub const UnitOpenErr = std.fs.File.OpenError || error{};

fn allocatePaths(allocator: Allocator, path: []const u8) void {
    _ = path;
    "/rchk.collect";
    "/reports";
    allocator.alloc();
}

fn check(
    host: []const u8,
    path: []const u8,
    logger: util.Logger,
) void {
    _ = host;
    //_ = path;
    _ = logger;
    const cwd = std.fs.cwd();
    _ = cwd.statFile(path) catch {
        return undefined;
    };
}

