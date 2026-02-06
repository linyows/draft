const std = @import("std");
const fs = std.fs;
const mem = std.mem;

pub fn getToday(allocator: mem.Allocator) ![]const u8 {
    const timestamp = std.time.timestamp();
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    return try std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
        year_day.year,
        @intFromEnum(month_day.month),
        month_day.day_index + 1,
    });
}

pub fn getUsername(allocator: mem.Allocator) ![]const u8 {
    const user_env = std.process.getEnvVarOwned(allocator, "USER") catch |err| {
        if (err == error.EnvironmentVariableNotFound) {
            return std.process.getEnvVarOwned(allocator, "USERNAME") catch {
                return error.UsernameNotFound;
            };
        }
        return err;
    };
    return user_env;
}

pub fn getNextId(allocator: mem.Allocator, cwd: fs.Dir, output_dir: []const u8) ![]const u8 {
    var max_id: u32 = 0;

    var dir = cwd.openDir(output_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            return try std.fmt.allocPrint(allocator, "{d}", .{1});
        }
        return err;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
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
    const today = try getToday(allocator);
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
    const username = getUsername(allocator) catch "fallback";
    defer if (!mem.eql(u8, username, "fallback")) allocator.free(username);

    try testing.expect(username.len > 0);
}

test "getNextId: returns 1 when directory not found" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const next_id = try getNextId(allocator, tmp.dir, "nonexistent");
    defer allocator.free(next_id);

    try testing.expectEqualStrings("1", next_id);
}

test "getNextId: returns 1 when directory is empty" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makeDir("docs");

    const next_id = try getNextId(allocator, tmp.dir, "docs");
    defer allocator.free(next_id);

    try testing.expectEqualStrings("1", next_id);
}

test "getNextId: returns next id with 3-digit filenames" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makeDir("docs");
    var docs = try tmp.dir.openDir("docs", .{});
    defer docs.close();

    // Create 001-foo.md, 002-bar.md
    {
        const f = try docs.createFile("001-foo.md", .{});
        f.close();
    }
    {
        const f = try docs.createFile("002-bar.md", .{});
        f.close();
    }

    const next_id = try getNextId(allocator, tmp.dir, "docs");
    defer allocator.free(next_id);

    try testing.expectEqualStrings("3", next_id);
}

test "getNextId: returns next id with 4-digit filenames" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makeDir("docs");
    var docs = try tmp.dir.openDir("docs", .{});
    defer docs.close();

    // Create 0001-foo.md, 0002-bar.md
    {
        const f = try docs.createFile("0001-foo.md", .{});
        f.close();
    }
    {
        const f = try docs.createFile("0002-bar.md", .{});
        f.close();
    }

    const next_id = try getNextId(allocator, tmp.dir, "docs");
    defer allocator.free(next_id);

    try testing.expectEqualStrings("3", next_id);
}

test "getNextId: skips non-numeric filenames" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makeDir("docs");
    var docs = try tmp.dir.openDir("docs", .{});
    defer docs.close();

    {
        const f = try docs.createFile("0001-foo.md", .{});
        f.close();
    }
    {
        const f = try docs.createFile("README.md", .{});
        f.close();
    }
    {
        const f = try docs.createFile("notes.md", .{});
        f.close();
    }

    const next_id = try getNextId(allocator, tmp.dir, "docs");
    defer allocator.free(next_id);

    try testing.expectEqualStrings("2", next_id);
}
