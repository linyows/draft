const std = @import("std");
const fs = std.fs;
const mem = std.mem;

const config = @import("config.zig");
const template = @import("template.zig");
const index = @import("index.zig");
const utils = @import("utils.zig");

const Config = config.Config;
const loadConfig = config.loadConfig;
const replaceVariables = template.replaceVariables;
const DocumentMeta = index.DocumentMeta;
const extractDocumentMeta = index.extractDocumentMeta;
const expandIndex = index.expandIndex;
const getToday = utils.getToday;
const getUsername = utils.getUsername;
const getNextId = utils.getNextId;

const default_config_json = @embedFile("templates/config.json");
const default_adr_template = @embedFile("templates/adr.md");
const default_adr_index_template = @embedFile("templates/adr-index.md");
const default_design_template = @embedFile("templates/design.md");
const default_design_index_template = @embedFile("templates/design-index.md");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    const command = args[1];

    if (mem.eql(u8, command, "init")) {
        try runInit(allocator);
    } else if (mem.eql(u8, command, "help") or mem.eql(u8, command, "--help") or mem.eql(u8, command, "-h")) {
        printUsage();
    } else if (mem.eql(u8, command, "version") or mem.eql(u8, command, "--version") or mem.eql(u8, command, "-v")) {
        printVersion();
    } else {
        if (args.len < 3) {
            std.debug.print("Error: Missing argument\n", .{});
            std.debug.print("Usage: draft <template> \"<title>\" or draft <template> index\n", .{});
            return;
        }
        const template_name = command;
        const second_arg = args[2];

        if (mem.eql(u8, second_arg, "index")) {
            try runIndex(allocator, template_name);
        } else {
            try runGenerate(allocator, template_name, second_arg);
        }
    }
}

fn printUsage() void {
    const usage =
        \\
        \\  ____  ____     _    ____ _____
        \\ |  _ \|  _ \   / \  |  __|_   _|
        \\ | | | | |_) | / _ \ | |_   | |
        \\ | |_| |  _ < / ___ \|  _|  | |
        \\ |____/|_| \_\_/   \_\_|    |_|
        \\
        \\ Markdown template generator
        \\
        \\Usage:
        \\  draft init                Initialize .draft directory with config and templates
        \\  draft <template> <title>  Generate a markdown file from template
        \\  draft <template> index    Generate index file (e.g., README.md)
        \\  draft help                Show this help message
        \\  draft version             Show version
        \\
        \\Examples:
        \\  draft init
        \\  draft adr "Authentication System Design"
        \\  draft design "API Design"
        \\  draft adr index
        \\
        \\Template Variables:
        \\  {{@title}}  - Title specified as argument
        \\  {{@today}}  - Today's date (YYYY-MM-DD)
        \\  {{@date}}   - Today's date (YYYY-MM-DD)
        \\  {{@name}}   - Current user name
        \\  {{@id}}     - Incremental ID (001, 002, ...)
        \\  {{@id{N}}}  - Incremental ID with N digits (e.g., {{@id{4}}} -> 0001)
        \\
        \\Index Variables:
        \\  {{@index}}                    - Document list table (default: @title|@date|@name)
        \\  {{@index{@id|@title|@status}}} - Custom format table
        \\
    ;
    std.debug.print("{s}", .{usage});
}

fn printVersion() void {
    std.debug.print("draft version 0.1.0\n", .{});
}

fn runInit(allocator: mem.Allocator) !void {
    _ = allocator;

    const cwd = fs.cwd();

    cwd.makePath(".draft/templates") catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Create config file
    if (cwd.createFile(".draft/config.json", .{ .exclusive = true })) |config_file| {
        defer config_file.close();
        try config_file.writeAll(default_config_json);
        std.debug.print("Created: .draft/config.json\n", .{});
    } else |err| {
        if (err == error.PathAlreadyExists) {
            std.debug.print("Already exists: .draft/config.json\n", .{});
        } else {
            return err;
        }
    }

    // Create adr template
    if (cwd.createFile(".draft/templates/adr.md", .{ .exclusive = true })) |adr_file| {
        defer adr_file.close();
        try adr_file.writeAll(default_adr_template);
        std.debug.print("Created: .draft/templates/adr.md\n", .{});
    } else |err| {
        if (err == error.PathAlreadyExists) {
            std.debug.print("Already exists: .draft/templates/adr.md\n", .{});
        } else {
            return err;
        }
    }

    // Create adr-index template
    if (cwd.createFile(".draft/templates/adr-index.md", .{ .exclusive = true })) |adr_index_file| {
        defer adr_index_file.close();
        try adr_index_file.writeAll(default_adr_index_template);
        std.debug.print("Created: .draft/templates/adr-index.md\n", .{});
    } else |err| {
        if (err == error.PathAlreadyExists) {
            std.debug.print("Already exists: .draft/templates/adr-index.md\n", .{});
        } else {
            return err;
        }
    }

    // Create design template
    if (cwd.createFile(".draft/templates/design.md", .{ .exclusive = true })) |design_file| {
        defer design_file.close();
        try design_file.writeAll(default_design_template);
        std.debug.print("Created: .draft/templates/design.md\n", .{});
    } else |err| {
        if (err == error.PathAlreadyExists) {
            std.debug.print("Already exists: .draft/templates/design.md\n", .{});
        } else {
            return err;
        }
    }

    // Create design-index template
    if (cwd.createFile(".draft/templates/design-index.md", .{ .exclusive = true })) |design_index_file| {
        defer design_index_file.close();
        try design_index_file.writeAll(default_design_index_template);
        std.debug.print("Created: .draft/templates/design-index.md\n", .{});
    } else |err| {
        if (err == error.PathAlreadyExists) {
            std.debug.print("Already exists: .draft/templates/design-index.md\n", .{});
        } else {
            return err;
        }
    }

    std.debug.print("\nInitialization complete!\n", .{});
}

fn runGenerate(allocator: mem.Allocator, template_name: []const u8, title: []const u8) !void {
    const cwd = fs.cwd();

    const cfg = try loadConfig(allocator, cwd);
    defer allocator.free(cfg.templates_dir);
    defer allocator.free(cfg.output_dir);
    defer allocator.free(cfg.filename_format);

    const template_path = try std.fmt.allocPrint(allocator, "{s}/{s}.md", .{ cfg.templates_dir, template_name });
    defer allocator.free(template_path);

    const template_content = cwd.readFileAlloc(allocator, template_path, 1024 * 1024) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: Template not found: {s}\n", .{template_path});
            std.debug.print("Run 'draft init' to create default templates or create your own.\n", .{});
            return;
        }
        return err;
    };
    defer allocator.free(template_content);

    const today = getToday(allocator) catch "0000-00-00";
    defer if (!mem.eql(u8, today, "0000-00-00")) allocator.free(today);

    const username = getUsername(allocator) catch "unknown";
    defer if (!mem.eql(u8, username, "unknown")) allocator.free(username);

    const next_id = try getNextId(allocator, cwd, cfg.output_dir);
    defer allocator.free(next_id);

    const output_content = try replaceVariables(allocator, template_content, title, today, username, next_id);
    defer allocator.free(output_content);

    const output_filename = try replaceVariables(allocator, cfg.filename_format, title, today, username, next_id);
    defer allocator.free(output_filename);

    const output_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ cfg.output_dir, output_filename });
    defer allocator.free(output_path);

    const dir_end = mem.lastIndexOfScalar(u8, output_path, '/');
    if (dir_end) |end| {
        const dir_path = output_path[0..end];
        cwd.makePath(dir_path) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }

    const output_file = cwd.createFile(output_path, .{ .exclusive = true }) catch |err| {
        if (err == error.PathAlreadyExists) {
            std.debug.print("Error: File already exists: {s}\n", .{output_path});
            return;
        }
        return err;
    };
    defer output_file.close();
    try output_file.writeAll(output_content);

    std.debug.print("Created: {s}\n", .{output_path});
}

fn runIndex(allocator: mem.Allocator, template_name: []const u8) !void {
    const cwd = fs.cwd();

    const cfg = try loadConfig(allocator, cwd);
    defer allocator.free(cfg.templates_dir);
    defer allocator.free(cfg.output_dir);
    defer allocator.free(cfg.filename_format);

    const template_path = try std.fmt.allocPrint(allocator, "{s}/{s}-index.md", .{ cfg.templates_dir, template_name });
    defer allocator.free(template_path);

    const template_content = cwd.readFileAlloc(allocator, template_path, 1024 * 1024) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: Index template not found: {s}\n", .{template_path});
            std.debug.print("Run 'draft init' to create default templates.\n", .{});
            return;
        }
        return err;
    };
    defer allocator.free(template_content);

    // Collect document metadata
    var docs = std.ArrayListUnmanaged(DocumentMeta){};
    defer {
        for (docs.items) |doc| {
            allocator.free(doc.filename);
            allocator.free(doc.id);
            allocator.free(doc.title);
            allocator.free(doc.date);
            allocator.free(doc.name);
            allocator.free(doc.status);
        }
        docs.deinit(allocator);
    }

    var dir = cwd.openDir(cfg.output_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: Output directory not found: {s}\n", .{cfg.output_dir});
            return;
        }
        return err;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!mem.endsWith(u8, entry.name, ".md")) continue;
        if (mem.eql(u8, entry.name, "README.md")) continue;

        const file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ cfg.output_dir, entry.name });
        defer allocator.free(file_path);

        const content = cwd.readFileAlloc(allocator, file_path, 1024 * 1024) catch continue;
        defer allocator.free(content);

        const meta = try extractDocumentMeta(allocator, entry.name, content);
        try docs.append(allocator, meta);
    }

    // Sort by ID
    std.mem.sort(DocumentMeta, docs.items, {}, struct {
        fn lessThan(_: void, a: DocumentMeta, b: DocumentMeta) bool {
            return std.mem.order(u8, a.id, b.id) == .lt;
        }
    }.lessThan);

    // Expand @index variable
    const output_content = try expandIndex(allocator, template_content, docs.items);
    defer allocator.free(output_content);

    const output_path = try std.fmt.allocPrint(allocator, "{s}/README.md", .{cfg.output_dir});
    defer allocator.free(output_path);

    // Write or overwrite README.md
    const output_file = try cwd.createFile(output_path, .{});
    defer output_file.close();
    try output_file.writeAll(output_content);

    std.debug.print("Created: {s}\n", .{output_path});
}

// Re-export tests from submodules
test {
    _ = @import("config.zig");
    _ = @import("template.zig");
    _ = @import("index.zig");
    _ = @import("utils.zig");
}
