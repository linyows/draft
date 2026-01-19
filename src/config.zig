const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const json = std.json;

pub const TemplateConfig = struct {
    output_dir: ?[]const u8 = null,
    filename_format: ?[]const u8 = null,
};

pub const Config = struct {
    templates_dir: []const u8 = ".draft/templates",
    output_dir: []const u8 = "docs",
    filename_format: []const u8 = "{{@title}}.md",
    templates: ?json.ArrayHashMap(TemplateConfig) = null,
};

pub fn getOutputDir(cfg: Config, template_name: []const u8) []const u8 {
    if (cfg.templates) |templates| {
        if (templates.map.get(template_name)) |template_config| {
            if (template_config.output_dir) |output_dir| {
                return output_dir;
            }
        }
    }
    return cfg.output_dir;
}

pub fn getFilenameFormat(cfg: Config, template_name: []const u8) []const u8 {
    if (cfg.templates) |templates| {
        if (templates.map.get(template_name)) |template_config| {
            if (template_config.filename_format) |filename_format| {
                return filename_format;
            }
        }
    }
    return cfg.filename_format;
}

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

    // Dupe templates if present
    var templates: ?json.ArrayHashMap(TemplateConfig) = null;
    if (parsed.value.templates) |parsed_templates| {
        var new_map = json.ArrayHashMap(TemplateConfig){};
        var iter = parsed_templates.map.iterator();
        while (iter.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const value = TemplateConfig{
                .output_dir = if (entry.value_ptr.output_dir) |od| try allocator.dupe(u8, od) else null,
                .filename_format = if (entry.value_ptr.filename_format) |ff| try allocator.dupe(u8, ff) else null,
            };
            try new_map.map.put(allocator, key, value);
        }
        templates = new_map;
    }

    return Config{
        .templates_dir = try allocator.dupe(u8, parsed.value.templates_dir),
        .output_dir = try allocator.dupe(u8, parsed.value.output_dir),
        .filename_format = try allocator.dupe(u8, parsed.value.filename_format),
        .templates = templates,
    };
}

pub fn freeConfig(allocator: mem.Allocator, cfg: *Config) void {
    allocator.free(cfg.templates_dir);
    allocator.free(cfg.output_dir);
    allocator.free(cfg.filename_format);
    if (cfg.templates) |*templates| {
        var iter = templates.map.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            if (entry.value_ptr.output_dir) |od| allocator.free(od);
            if (entry.value_ptr.filename_format) |ff| allocator.free(ff);
        }
        templates.map.deinit(allocator);
    }
}

// =============================================================================
// Tests
// =============================================================================

const testing = std.testing;

test "Config: default values" {
    const cfg = Config{};

    try testing.expectEqualStrings(".draft/templates", cfg.templates_dir);
    try testing.expectEqualStrings("docs", cfg.output_dir);
    try testing.expectEqualStrings("{{@title}}.md", cfg.filename_format);
    try testing.expect(cfg.templates == null);
}

test "Config: getOutputDir returns global when no template config" {
    const cfg = Config{
        .output_dir = "docs",
    };

    try testing.expectEqualStrings("docs", getOutputDir(cfg, "adr"));
    try testing.expectEqualStrings("docs", getOutputDir(cfg, "design"));
}

test "Config: getFilenameFormat returns global when no template config" {
    const cfg = Config{
        .filename_format = "{{@title}}.md",
    };

    try testing.expectEqualStrings("{{@title}}.md", getFilenameFormat(cfg, "adr"));
    try testing.expectEqualStrings("{{@title}}.md", getFilenameFormat(cfg, "design"));
}

test "Config: getOutputDir returns template-specific config" {
    var templates = json.ArrayHashMap(TemplateConfig){};
    try templates.map.put(testing.allocator, "adr", TemplateConfig{
        .output_dir = "docs/adrs",
        .filename_format = null,
    });
    defer templates.map.deinit(testing.allocator);

    const cfg = Config{
        .output_dir = "docs",
        .templates = templates,
    };

    try testing.expectEqualStrings("docs/adrs", getOutputDir(cfg, "adr"));
    try testing.expectEqualStrings("docs", getOutputDir(cfg, "design"));
}

test "Config: getFilenameFormat returns template-specific config" {
    var templates = json.ArrayHashMap(TemplateConfig){};
    try templates.map.put(testing.allocator, "adr", TemplateConfig{
        .output_dir = null,
        .filename_format = "{{@id{4}}}-{{@title}}.md",
    });
    defer templates.map.deinit(testing.allocator);

    const cfg = Config{
        .filename_format = "{{@title}}.md",
        .templates = templates,
    };

    try testing.expectEqualStrings("{{@id{4}}}-{{@title}}.md", getFilenameFormat(cfg, "adr"));
    try testing.expectEqualStrings("{{@title}}.md", getFilenameFormat(cfg, "design"));
}
