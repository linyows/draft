const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const Dir = std.Io.Dir;
const Environ = std.process.Environ;

pub fn getToday(allocator: mem.Allocator, io: Io) ![]const u8 {
    const now = Io.Timestamp.now(io, .real);
    const seconds = @divFloor(now.nanoseconds, std.time.ns_per_s);
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(seconds) };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    return try std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
        year_day.year,
        @intFromEnum(month_day.month),
        month_day.day_index + 1,
    });
}

pub fn getUsername(allocator: mem.Allocator, environ: Environ) ![]const u8 {
    const user_env = environ.getAlloc(allocator, "USER") catch |err| {
        if (err == error.EnvironmentVariableMissing) {
            return environ.getAlloc(allocator, "USERNAME") catch {
                return error.UsernameNotFound;
            };
        }
        return err;
    };
    return user_env;
}

pub fn getNextId(allocator: mem.Allocator, io: Io, cwd: Dir, output_dir: []const u8) ![]const u8 {
    var max_id: u32 = 0;

    var dir = cwd.openDir(io, output_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            return try std.fmt.allocPrint(allocator, "{d}", .{1});
        }
        return err;
    };
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!mem.endsWith(u8, entry.name, ".md")) continue;

        // Extract leading digits from filename
        var digit_end: usize = 0;
        while (digit_end < entry.name.len and entry.name[digit_end] >= '0' and entry.name[digit_end] <= '9') {
            digit_end += 1;
        }
        if (digit_end == 0) continue;

        const id_part = entry.name[0..digit_end];
        const id = std.fmt.parseInt(u32, id_part, 10) catch continue;
        if (id > max_id) {
            max_id = id;
        }
    }

    return try std.fmt.allocPrint(allocator, "{d}", .{max_id + 1});
}

// =============================================================================
// Tests
// =============================================================================

const testing = std.testing;

test "getToday: format is YYYY-MM-DD" {
    const allocator = testing.allocator;
    const today = try getToday(allocator, testing.io);
    defer allocator.free(today);

    try testing.expectEqual(@as(usize, 10), today.len);
    try testing.expectEqual(@as(u8, '-'), today[4]);
    try testing.expectEqual(@as(u8, '-'), today[7]);

    _ = std.fmt.parseInt(u32, today[0..4], 10) catch {
        return error.InvalidYear;
    };
    _ = std.fmt.parseInt(u32, today[5..7], 10) catch {
        return error.InvalidMonth;
    };
    _ = std.fmt.parseInt(u32, today[8..10], 10) catch {
        return error.InvalidDay;
    };
}

test "getUsername: returns non-empty string" {
    const allocator = testing.allocator;
    const username = getUsername(allocator, testing.environ) catch "fallback";
    defer if (!mem.eql(u8, username, "fallback")) allocator.free(username);

    try testing.expect(username.len > 0);
}

test "getNextId: returns 1 when directory not found" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const next_id = try getNextId(allocator, testing.io, tmp.dir, "nonexistent");
    defer allocator.free(next_id);

    try testing.expectEqualStrings("1", next_id);
}

test "getNextId: returns 1 when directory is empty" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(testing.io, "docs", .default_dir);

    const next_id = try getNextId(allocator, testing.io, tmp.dir, "docs");
    defer allocator.free(next_id);

    try testing.expectEqualStrings("1", next_id);
}

test "getNextId: returns next id with 3-digit filenames" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(testing.io, "docs", .default_dir);
    var docs = try tmp.dir.openDir(testing.io, "docs", .{});
    defer docs.close(testing.io);

    // Create 001-foo.md, 002-bar.md
    {
        const f = try docs.createFile(testing.io, "001-foo.md", .{});
        f.close(testing.io);
    }
    {
        const f = try docs.createFile(testing.io, "002-bar.md", .{});
        f.close(testing.io);
    }

    const next_id = try getNextId(allocator, testing.io, tmp.dir, "docs");
    defer allocator.free(next_id);

    try testing.expectEqualStrings("3", next_id);
}

test "getNextId: returns next id with 4-digit filenames" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(testing.io, "docs", .default_dir);
    var docs = try tmp.dir.openDir(testing.io, "docs", .{});
    defer docs.close(testing.io);

    // Create 0001-foo.md, 0002-bar.md
    {
        const f = try docs.createFile(testing.io, "0001-foo.md", .{});
        f.close(testing.io);
    }
    {
        const f = try docs.createFile(testing.io, "0002-bar.md", .{});
        f.close(testing.io);
    }

    const next_id = try getNextId(allocator, testing.io, tmp.dir, "docs");
    defer allocator.free(next_id);

    try testing.expectEqualStrings("3", next_id);
}

test "getNextId: skips non-numeric filenames" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(testing.io, "docs", .default_dir);
    var docs = try tmp.dir.openDir(testing.io, "docs", .{});
    defer docs.close(testing.io);

    {
        const f = try docs.createFile(testing.io, "0001-foo.md", .{});
        f.close(testing.io);
    }
    {
        const f = try docs.createFile(testing.io, "README.md", .{});
        f.close(testing.io);
    }
    {
        const f = try docs.createFile(testing.io, "notes.md", .{});
        f.close(testing.io);
    }

    const next_id = try getNextId(allocator, testing.io, tmp.dir, "docs");
    defer allocator.free(next_id);

    try testing.expectEqualStrings("2", next_id);
}
