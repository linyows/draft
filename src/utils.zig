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
            return try std.fmt.allocPrint(allocator, "{d:0>3}", .{1});
        }
        return err;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!mem.endsWith(u8, entry.name, ".md")) continue;

        if (entry.name.len >= 3) {
            const id_part = entry.name[0..3];
            const id = std.fmt.parseInt(u32, id_part, 10) catch continue;
            if (id > max_id) {
                max_id = id;
            }
        }
    }

    return try std.fmt.allocPrint(allocator, "{d:0>3}", .{max_id + 1});
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
