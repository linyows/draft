const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const json = std.json;

pub const Config = struct {
    templates_dir: []const u8 = ".draft/templates",
    output_dir: []const u8 = "docs",
    filename_format: []const u8 = "{{@title}}.md",
};

pub fn loadConfig(allocator: mem.Allocator, cwd: fs.Dir) !Config {
    const config_content = cwd.readFileAlloc(allocator, ".draft/config.json", 1024 * 1024) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: Config file not found. Run 'draft init' first.\n", .{});
            return error.ConfigNotFound;
        }
        return err;
    };
    defer allocator.free(config_content);

    const parsed = try json.parseFromSlice(Config, allocator, config_content, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    return Config{
        .templates_dir = try allocator.dupe(u8, parsed.value.templates_dir),
        .output_dir = try allocator.dupe(u8, parsed.value.output_dir),
        .filename_format = try allocator.dupe(u8, parsed.value.filename_format),
    };
}

// =============================================================================
// Tests
// =============================================================================

const testing = std.testing;

test "Config: default values" {
    const config = Config{};

    try testing.expectEqualStrings(".draft/templates", config.templates_dir);
    try testing.expectEqualStrings("docs", config.output_dir);
    try testing.expectEqualStrings("{{@title}}.md", config.filename_format);
}
