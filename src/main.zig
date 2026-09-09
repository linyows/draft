const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const Dir = std.Io.Dir;
const Environ = std.process.Environ;
const build_options = @import("build_options");

const config = @import("config.zig");
const template = @import("template.zig");
const index = @import("index.zig");
const utils = @import("utils.zig");

const Config = config.Config;
const loadConfig = config.loadConfig;
const freeConfig = config.freeConfig;
const getOutputDir = config.getOutputDir;
const getFilenameFormat = config.getFilenameFormat;
const replaceVariables = template.replaceVariables;
const DocumentMeta = index.DocumentMeta;
const extractDocumentMeta = index.extractDocumentMeta;
const expandIndex = index.expandIndex;
const extractSortConfigFromTemplate = index.extractSortConfigFromTemplate;
const getDefaultSortConfig = index.getDefaultSortConfig;
const sortDocuments = index.sortDocuments;
const getToday = utils.getToday;
const getUsername = utils.getUsername;
const getNextId = utils.getNextId;

const default_config_json = @embedFile("templates/config.json");
const default_adr_template = @embedFile("templates/adr.md");
const default_adr_index_template = @embedFile("templates/adr-index.md");
const default_design_template = @embedFile("templates/design.md");
const default_design_index_template = @embedFile("templates/design-index.md");
const logo_text = @embedFile("assets/logo.txt");
const desc_text = @embedFile("assets/desc.txt");
const usage_text = @embedFile("assets/usage.txt");

// ANSI color codes
const gold = "\x1b[38;5;178m";
const dim = "\x1b[2m";
const reset = "\x1b[0m";

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2) {
        printUsage();
        return;
    }

    const command = args[1];

    if (mem.eql(u8, command, "init")) {
        try runInit(io);
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
            try runIndex(allocator, io, template_name);
        } else {
            try runGenerate(allocator, io, init.minimal.environ, template_name, second_arg);
        }
    }
}

fn printUsage() void {
    std.debug.print("{s}{s}{s}{s}{s}{s}\n{s}", .{ gold, logo_text, reset, dim, desc_text, reset, usage_text });
}

fn printVersion() void {
    std.debug.print("draft version {s}\n", .{build_options.version});
}

fn runInit(io: Io) !void {
    const cwd = Dir.cwd();

    try cwd.createDirPath(io, ".draft/templates");

    // Create config file
    if (cwd.createFile(io, ".draft/config.json", .{ .exclusive = true })) |config_file| {
        defer config_file.close(io);
        try config_file.writeStreamingAll(io, default_config_json);
        std.debug.print("Created: .draft/config.json\n", .{});
    } else |err| {
        if (err == error.PathAlreadyExists) {
            std.debug.print("Already exists: .draft/config.json\n", .{});
        } else {
            return err;
        }
    }

    // Create adr template
    if (cwd.createFile(io, ".draft/templates/adr.md", .{ .exclusive = true })) |adr_file| {
        defer adr_file.close(io);
        try adr_file.writeStreamingAll(io, default_adr_template);
        std.debug.print("Created: .draft/templates/adr.md\n", .{});
    } else |err| {
        if (err == error.PathAlreadyExists) {
            std.debug.print("Already exists: .draft/templates/adr.md\n", .{});
        } else {
            return err;
        }
    }

    // Create adr-index template
    if (cwd.createFile(io, ".draft/templates/adr-index.md", .{ .exclusive = true })) |adr_index_file| {
        defer adr_index_file.close(io);
        try adr_index_file.writeStreamingAll(io, default_adr_index_template);
        std.debug.print("Created: .draft/templates/adr-index.md\n", .{});
    } else |err| {
        if (err == error.PathAlreadyExists) {
            std.debug.print("Already exists: .draft/templates/adr-index.md\n", .{});
        } else {
            return err;
        }
    }

    // Create design template
    if (cwd.createFile(io, ".draft/templates/design.md", .{ .exclusive = true })) |design_file| {
        defer design_file.close(io);
        try design_file.writeStreamingAll(io, default_design_template);
        std.debug.print("Created: .draft/templates/design.md\n", .{});
    } else |err| {
        if (err == error.PathAlreadyExists) {
            std.debug.print("Already exists: .draft/templates/design.md\n", .{});
        } else {
            return err;
        }
    }

    // Create design-index template
    if (cwd.createFile(io, ".draft/templates/design-index.md", .{ .exclusive = true })) |design_index_file| {
        defer design_index_file.close(io);
        try design_index_file.writeStreamingAll(io, default_design_index_template);
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

fn runGenerate(allocator: mem.Allocator, io: Io, environ: Environ, template_name: []const u8, title: []const u8) !void {
    const cwd = Dir.cwd();

    var cfg = try loadConfig(allocator, io, cwd);
    defer freeConfig(allocator, &cfg);

    const output_dir = getOutputDir(cfg, template_name);
    const filename_format = getFilenameFormat(cfg, template_name);

    const template_path = try std.fmt.allocPrint(allocator, "{s}/{s}.md", .{ cfg.templates_dir, template_name });
    defer allocator.free(template_path);

    const template_content = cwd.readFileAlloc(io, template_path, allocator, .limited(1024 * 1024)) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: Template not found: {s}\n", .{template_path});
            std.debug.print("Run 'draft init' to create default templates or create your own.\n", .{});
            return;
        }
        return err;
    };
    defer allocator.free(template_content);

    const today = getToday(allocator, io) catch "0000-00-00";
    defer if (!mem.eql(u8, today, "0000-00-00")) allocator.free(today);

    const username = getUsername(allocator, environ) catch "unknown";
    defer if (!mem.eql(u8, username, "unknown")) allocator.free(username);

    const next_id = try getNextId(allocator, io, cwd, output_dir);
    defer allocator.free(next_id);

    const output_content = try replaceVariables(allocator, template_content, title, today, username, next_id);
    defer allocator.free(output_content);

    const output_filename = try replaceVariables(allocator, filename_format, title, today, username, next_id);
    defer allocator.free(output_filename);

    const output_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ output_dir, output_filename });
    defer allocator.free(output_path);

    const dir_end = mem.lastIndexOfScalar(u8, output_path, '/');
    if (dir_end) |end| {
        const dir_path = output_path[0..end];
        try cwd.createDirPath(io, dir_path);
    }

    const output_file = cwd.createFile(io, output_path, .{ .exclusive = true }) catch |err| {
        if (err == error.PathAlreadyExists) {
            std.debug.print("Error: File already exists: {s}\n", .{output_path});
            return;
        }
        return err;
    };
    defer output_file.close(io);
    try output_file.writeStreamingAll(io, output_content);

    std.debug.print("Created: {s}\n", .{output_path});
}

fn runIndex(allocator: mem.Allocator, io: Io, template_name: []const u8) !void {
    const cwd = Dir.cwd();

    var cfg = try loadConfig(allocator, io, cwd);
    defer freeConfig(allocator, &cfg);

    const output_dir = getOutputDir(cfg, template_name);

    const template_path = try std.fmt.allocPrint(allocator, "{s}/{s}-index.md", .{ cfg.templates_dir, template_name });
    defer allocator.free(template_path);

    const template_content = cwd.readFileAlloc(io, template_path, allocator, .limited(1024 * 1024)) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: Index template not found: {s}\n", .{template_path});
            std.debug.print("Run 'draft init' to create default templates.\n", .{});
            return;
        }
        return err;
    };
    defer allocator.free(template_content);

    // Collect document metadata
    var docs = std.ArrayListUnmanaged(DocumentMeta).empty;
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

    var dir = cwd.openDir(io, output_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: Output directory not found: {s}\n", .{output_dir});
            return;
        }
        return err;
    };
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!mem.endsWith(u8, entry.name, ".md")) continue;
        if (mem.eql(u8, entry.name, "README.md")) continue;

        const file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ output_dir, entry.name });
        defer allocator.free(file_path);

        const content = cwd.readFileAlloc(io, file_path, allocator, .limited(1024 * 1024)) catch continue;
        defer allocator.free(content);

        // Get file modification time
        const stat = dir.statFile(io, entry.name, .{}) catch continue;
        const mtime: i128 = stat.mtime.nanoseconds;

        const meta = try extractDocumentMeta(allocator, entry.name, content, mtime);
        try docs.append(allocator, meta);
    }

    // Determine sort configuration
    const sort_config = extractSortConfigFromTemplate(template_content) orelse
        getDefaultSortConfig(docs.items);

    // Sort documents
    sortDocuments(docs.items, sort_config);

    // Expand @index variable
    const output_content = try expandIndex(allocator, template_content, docs.items);
    defer allocator.free(output_content);

    const output_path = try std.fmt.allocPrint(allocator, "{s}/README.md", .{output_dir});
    defer allocator.free(output_path);

    // Write or overwrite README.md
    const output_file = try cwd.createFile(io, output_path, .{});
    defer output_file.close(io);
    try output_file.writeStreamingAll(io, output_content);

    std.debug.print("Created: {s}\n", .{output_path});
}

// Re-export tests from submodules
test {
    _ = @import("config.zig");
    _ = @import("template.zig");
    _ = @import("index.zig");
    _ = @import("utils.zig");
}
