const std = @import("std");
const mem = std.mem;

pub const DocumentMeta = struct {
    filename: []const u8,
    id: []const u8,
    title: []const u8,
    date: []const u8,
    name: []const u8,
    status: []const u8,
    mtime: i128, // File modification time in nanoseconds
};

pub const SortOrder = enum {
    asc,
    desc,
};

pub const SortConfig = struct {
    field: []const u8,
    order: SortOrder,
};

pub fn extractDocumentMeta(allocator: mem.Allocator, filename: []const u8, content: []const u8, mtime: i128) !DocumentMeta {
    var meta = DocumentMeta{
        .filename = try allocator.dupe(u8, filename),
        .id = try allocator.dupe(u8, ""),
        .title = try allocator.dupe(u8, ""),
        .date = try allocator.dupe(u8, ""),
        .name = try allocator.dupe(u8, ""),
        .status = try allocator.dupe(u8, ""),
        .mtime = mtime,
    };

    // Extract ID from filename (first 3 chars if numeric)
    if (filename.len >= 3) {
        const id_part = filename[0..3];
        if (std.fmt.parseInt(u32, id_part, 10)) |_| {
            allocator.free(meta.id);
            meta.id = try allocator.dupe(u8, id_part);
        } else |_| {}
    }

    // Parse content line by line
    var lines = mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = mem.trim(u8, line, " \t\r");

        // Extract title from first heading
        if (mem.startsWith(u8, trimmed, "# ") and meta.title.len == 0) {
            allocator.free(meta.title);
            meta.title = try allocator.dupe(u8, trimmed[2..]);
            continue;
        }

        // Extract metadata fields
        if (mem.startsWith(u8, trimmed, "- ID: ")) {
            allocator.free(meta.id);
            meta.id = try allocator.dupe(u8, trimmed[6..]);
        } else if (mem.startsWith(u8, trimmed, "- Date: ")) {
            allocator.free(meta.date);
            meta.date = try allocator.dupe(u8, trimmed[8..]);
        } else if (mem.startsWith(u8, trimmed, "- Author: ")) {
            allocator.free(meta.name);
            meta.name = try allocator.dupe(u8, trimmed[10..]);
        } else if (mem.startsWith(u8, trimmed, "- Status: ")) {
            allocator.free(meta.status);
            meta.status = try allocator.dupe(u8, trimmed[10..]);
        }
    }

    return meta;
}

/// Extract sort configuration from template
/// Returns null if no sort specification found in template
pub fn extractSortConfigFromTemplate(template: []const u8) ?SortConfig {
    const index_start = "{{@index";
    if (mem.indexOf(u8, template, index_start)) |start_idx| {
        const after_start = template[start_idx + index_start.len ..];

        if (after_start.len > 0 and after_start[0] == '{') {
            // Custom format: {{@index{@id|@title|@status,asc:@id}}}
            if (mem.indexOf(u8, after_start, "}}}")) |close_idx| {
                const spec = after_start[1..close_idx];
                const parsed = parseIndexSpec(spec);
                if (parsed.sort_spec) |sort_spec| {
                    return parseSortSpec(sort_spec);
                }
            }
        }
    }
    return null;
}

pub fn expandIndex(allocator: mem.Allocator, template: []const u8, docs: []const DocumentMeta) ![]const u8 {
    var result = try allocator.dupe(u8, template);

    // Find {{@index}} or {{@index{...}}}
    const index_start = "{{@index";
    if (mem.indexOf(u8, result, index_start)) |start_idx| {
        const after_start = result[start_idx + index_start.len ..];

        var format: []const u8 = "@title|@date|@name"; // default format
        var end_idx: usize = 0;

        if (after_start.len > 0 and after_start[0] == '{') {
            // Custom format: {{@index{@id|@title|@status}}} or {{@index{@id|@title,asc:@id}}}
            if (mem.indexOf(u8, after_start, "}}}")) |close_idx| {
                const spec = after_start[1..close_idx];
                const parsed = parseIndexSpec(spec);
                format = parsed.format;
                end_idx = start_idx + index_start.len + close_idx + 3;
            }
        } else if (mem.indexOf(u8, after_start, "}}")) |close_idx| {
            // Default format: {{@index}}
            end_idx = start_idx + index_start.len + close_idx + 2;
        }

        if (end_idx > 0) {
            const table = try buildIndexTable(allocator, docs, format);
            defer allocator.free(table);

            const new_len = start_idx + table.len + (result.len - end_idx);
            var new_result = try allocator.alloc(u8, new_len);

            @memcpy(new_result[0..start_idx], result[0..start_idx]);
            @memcpy(new_result[start_idx .. start_idx + table.len], table);
            @memcpy(new_result[start_idx + table.len ..], result[end_idx..]);

            allocator.free(result);
            result = new_result;
        }
    }

    return result;
}

pub fn buildIndexTable(allocator: mem.Allocator, docs: []const DocumentMeta, format: []const u8) ![]const u8 {
    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(allocator);

    // Parse format columns
    var columns = std.ArrayListUnmanaged([]const u8){};
    defer columns.deinit(allocator);

    var col_iter = mem.splitScalar(u8, format, '|');
    while (col_iter.next()) |col| {
        try columns.append(allocator, mem.trim(u8, col, " "));
    }

    // Build header
    try buffer.appendSlice(allocator, "| ");
    for (columns.items, 0..) |col, i| {
        if (i > 0) try buffer.appendSlice(allocator, " | ");
        const header = getColumnHeader(col);
        try buffer.appendSlice(allocator, header);
    }
    try buffer.appendSlice(allocator, " |\n");

    // Build separator
    try buffer.appendSlice(allocator, "|");
    for (columns.items) |_| {
        try buffer.appendSlice(allocator, "------|");
    }
    try buffer.appendSlice(allocator, "\n");

    // Build rows
    for (docs) |doc| {
        try buffer.appendSlice(allocator, "| ");
        for (columns.items, 0..) |col, i| {
            if (i > 0) try buffer.appendSlice(allocator, " | ");
            const value = getColumnValue(doc, col);

            // First column with link
            if (i == 0) {
                try buffer.appendSlice(allocator, "[");
                try buffer.appendSlice(allocator, value);
                try buffer.appendSlice(allocator, "](./");
                try buffer.appendSlice(allocator, doc.filename);
                try buffer.appendSlice(allocator, ")");
            } else {
                try buffer.appendSlice(allocator, value);
            }
        }
        try buffer.appendSlice(allocator, " |\n");
    }

    return try buffer.toOwnedSlice(allocator);
}

pub fn getColumnHeader(col: []const u8) []const u8 {
    if (mem.eql(u8, col, "@id")) return "ID";
    if (mem.eql(u8, col, "@title")) return "Title";
    if (mem.eql(u8, col, "@date")) return "Date";
    if (mem.eql(u8, col, "@name")) return "Author";
    if (mem.eql(u8, col, "@status")) return "Status";
    return col;
}

pub fn getColumnValue(doc: DocumentMeta, col: []const u8) []const u8 {
    if (mem.eql(u8, col, "@id")) return doc.id;
    if (mem.eql(u8, col, "@title")) return doc.title;
    if (mem.eql(u8, col, "@date")) return doc.date;
    if (mem.eql(u8, col, "@name")) return doc.name;
    if (mem.eql(u8, col, "@status")) return doc.status;
    return "";
}

/// Parse sort specification from format string (e.g., "asc:@id" or "desc:@date")
pub fn parseSortSpec(sort_spec: []const u8) ?SortConfig {
    if (mem.startsWith(u8, sort_spec, "asc:")) {
        return SortConfig{
            .field = sort_spec[4..],
            .order = .asc,
        };
    } else if (mem.startsWith(u8, sort_spec, "desc:")) {
        return SortConfig{
            .field = sort_spec[5..],
            .order = .desc,
        };
    }
    return null;
}

/// Determine default sort configuration based on document metadata
/// - If documents have id: sort by id ascending
/// - Else if documents have date: sort by date descending
/// - Else: sort by mtime descending
pub fn getDefaultSortConfig(docs: []const DocumentMeta) SortConfig {
    // Check if any document has a non-empty id
    var has_id = false;
    var has_date = false;

    for (docs) |doc| {
        if (doc.id.len > 0) has_id = true;
        if (doc.date.len > 0) has_date = true;
    }

    if (has_id) {
        return SortConfig{ .field = "@id", .order = .asc };
    } else if (has_date) {
        return SortConfig{ .field = "@date", .order = .desc };
    } else {
        return SortConfig{ .field = "@mtime", .order = .desc };
    }
}

/// Sort documents by the given configuration
pub fn sortDocuments(docs: []DocumentMeta, sort_config: SortConfig) void {
    const Context = struct {
        config: SortConfig,

        fn compare(ctx: @This(), a: DocumentMeta, b: DocumentMeta) bool {
            const order_result = if (mem.eql(u8, ctx.config.field, "@mtime"))
                compareMtime(a, b)
            else
                compareStrings(getColumnValue(a, ctx.config.field), getColumnValue(b, ctx.config.field));

            return if (ctx.config.order == .asc) order_result == .lt else order_result == .gt;
        }

        fn compareMtime(a: DocumentMeta, b: DocumentMeta) std.math.Order {
            return std.math.order(a.mtime, b.mtime);
        }

        fn compareStrings(a_val: []const u8, b_val: []const u8) std.math.Order {
            return mem.order(u8, a_val, b_val);
        }
    };

    std.mem.sort(DocumentMeta, docs, Context{ .config = sort_config }, Context.compare);
}

/// Parse format and sort specification from index tag
/// Format: "@col1|@col2|@col3,asc:@field" or "@col1|@col2|@col3"
/// Returns (format, sort_spec)
pub fn parseIndexSpec(spec: []const u8) struct { format: []const u8, sort_spec: ?[]const u8 } {
    if (mem.lastIndexOfScalar(u8, spec, ',')) |comma_idx| {
        return .{
            .format = spec[0..comma_idx],
            .sort_spec = spec[comma_idx + 1 ..],
        };
    }
    return .{
        .format = spec,
        .sort_spec = null,
    };
}

// =============================================================================
// Tests
// =============================================================================

const testing = std.testing;

test "extractDocumentMeta: basic extraction" {
    const allocator = testing.allocator;
    const content =
        \\# Authentication System
        \\
        \\- ID: 001
        \\- Date: 2026-01-18
        \\- Author: linyows
        \\- Status: Accepted
        \\
        \\## Context
    ;

    const meta = try extractDocumentMeta(allocator, "001-auth.md", content, 1000000);
    defer {
        allocator.free(meta.filename);
        allocator.free(meta.id);
        allocator.free(meta.title);
        allocator.free(meta.date);
        allocator.free(meta.name);
        allocator.free(meta.status);
    }

    try testing.expectEqualStrings("001-auth.md", meta.filename);
    try testing.expectEqualStrings("001", meta.id);
    try testing.expectEqualStrings("Authentication System", meta.title);
    try testing.expectEqualStrings("2026-01-18", meta.date);
    try testing.expectEqualStrings("linyows", meta.name);
    try testing.expectEqualStrings("Accepted", meta.status);
    try testing.expectEqual(@as(i128, 1000000), meta.mtime);
}

test "extractDocumentMeta: id from filename" {
    const allocator = testing.allocator;
    const content = "# My Title\n\nSome content";

    const meta = try extractDocumentMeta(allocator, "042-my-doc.md", content, 2000000);
    defer {
        allocator.free(meta.filename);
        allocator.free(meta.id);
        allocator.free(meta.title);
        allocator.free(meta.date);
        allocator.free(meta.name);
        allocator.free(meta.status);
    }

    try testing.expectEqualStrings("042", meta.id);
    try testing.expectEqualStrings("My Title", meta.title);
}

test "getColumnHeader: maps column names" {
    try testing.expectEqualStrings("ID", getColumnHeader("@id"));
    try testing.expectEqualStrings("Title", getColumnHeader("@title"));
    try testing.expectEqualStrings("Date", getColumnHeader("@date"));
    try testing.expectEqualStrings("Author", getColumnHeader("@name"));
    try testing.expectEqualStrings("Status", getColumnHeader("@status"));
    try testing.expectEqualStrings("@unknown", getColumnHeader("@unknown"));
}

test "getColumnValue: returns correct values" {
    const doc = DocumentMeta{
        .filename = "test.md",
        .id = "001",
        .title = "Test Title",
        .date = "2026-01-18",
        .name = "linyows",
        .status = "Proposed",
        .mtime = 1000000,
    };

    try testing.expectEqualStrings("001", getColumnValue(doc, "@id"));
    try testing.expectEqualStrings("Test Title", getColumnValue(doc, "@title"));
    try testing.expectEqualStrings("2026-01-18", getColumnValue(doc, "@date"));
    try testing.expectEqualStrings("linyows", getColumnValue(doc, "@name"));
    try testing.expectEqualStrings("Proposed", getColumnValue(doc, "@status"));
    try testing.expectEqualStrings("", getColumnValue(doc, "@unknown"));
}

test "buildIndexTable: default format" {
    const allocator = testing.allocator;
    var docs = [_]DocumentMeta{
        .{
            .filename = "001-auth.md",
            .id = "001",
            .title = "Auth System",
            .date = "2026-01-18",
            .name = "linyows",
            .status = "Accepted",
            .mtime = 1000000,
        },
    };

    const table = try buildIndexTable(allocator, &docs, "@title|@date|@name");
    defer allocator.free(table);

    try testing.expect(mem.indexOf(u8, table, "| Title | Date | Author |") != null);
    try testing.expect(mem.indexOf(u8, table, "[Auth System](./001-auth.md)") != null);
    try testing.expect(mem.indexOf(u8, table, "2026-01-18") != null);
    try testing.expect(mem.indexOf(u8, table, "linyows") != null);
}

test "buildIndexTable: custom format with id and status" {
    const allocator = testing.allocator;
    var docs = [_]DocumentMeta{
        .{
            .filename = "001-auth.md",
            .id = "001",
            .title = "Auth System",
            .date = "2026-01-18",
            .name = "linyows",
            .status = "Accepted",
            .mtime = 1000000,
        },
    };

    const table = try buildIndexTable(allocator, &docs, "@id|@title|@status");
    defer allocator.free(table);

    try testing.expect(mem.indexOf(u8, table, "| ID | Title | Status |") != null);
    try testing.expect(mem.indexOf(u8, table, "[001](./001-auth.md)") != null);
    try testing.expect(mem.indexOf(u8, table, "Accepted") != null);
}

test "expandIndex: default format" {
    const allocator = testing.allocator;
    const template = "# Index\n\n{{@index}}\n\nFooter";
    var docs = [_]DocumentMeta{
        .{
            .filename = "001-test.md",
            .id = "001",
            .title = "Test",
            .date = "2026-01-18",
            .name = "linyows",
            .status = "Proposed",
            .mtime = 1000000,
        },
    };

    const result = try expandIndex(allocator, template, &docs);
    defer allocator.free(result);

    try testing.expect(mem.indexOf(u8, result, "# Index") != null);
    try testing.expect(mem.indexOf(u8, result, "| Title | Date | Author |") != null);
    try testing.expect(mem.indexOf(u8, result, "[Test](./001-test.md)") != null);
    try testing.expect(mem.indexOf(u8, result, "Footer") != null);
}

test "expandIndex: custom format" {
    const allocator = testing.allocator;
    const template = "# ADR\n\n{{@index{@id|@title|@status}}}\n";
    var docs = [_]DocumentMeta{
        .{
            .filename = "001-test.md",
            .id = "001",
            .title = "Test",
            .date = "2026-01-18",
            .name = "linyows",
            .status = "Accepted",
            .mtime = 1000000,
        },
    };

    const result = try expandIndex(allocator, template, &docs);
    defer allocator.free(result);

    try testing.expect(mem.indexOf(u8, result, "| ID | Title | Status |") != null);
    try testing.expect(mem.indexOf(u8, result, "[001](./001-test.md)") != null);
    try testing.expect(mem.indexOf(u8, result, "Accepted") != null);
}

test "expandIndex: custom format with sort spec" {
    const allocator = testing.allocator;
    const template = "# ADR\n\n{{@index{@id|@title,asc:@id}}}\n";
    var docs = [_]DocumentMeta{
        .{
            .filename = "001-test.md",
            .id = "001",
            .title = "Test",
            .date = "2026-01-18",
            .name = "linyows",
            .status = "Accepted",
            .mtime = 1000000,
        },
    };

    const result = try expandIndex(allocator, template, &docs);
    defer allocator.free(result);

    try testing.expect(mem.indexOf(u8, result, "| ID | Title |") != null);
    try testing.expect(mem.indexOf(u8, result, "[001](./001-test.md)") != null);
}

test "parseSortSpec: parses asc" {
    const config = parseSortSpec("asc:@id");
    try testing.expect(config != null);
    try testing.expectEqualStrings("@id", config.?.field);
    try testing.expectEqual(SortOrder.asc, config.?.order);
}

test "parseSortSpec: parses desc" {
    const config = parseSortSpec("desc:@date");
    try testing.expect(config != null);
    try testing.expectEqualStrings("@date", config.?.field);
    try testing.expectEqual(SortOrder.desc, config.?.order);
}

test "parseSortSpec: returns null for invalid" {
    try testing.expect(parseSortSpec("invalid") == null);
    try testing.expect(parseSortSpec("@id") == null);
}

test "parseIndexSpec: with sort spec" {
    const result = parseIndexSpec("@id|@title|@date,asc:@id");
    try testing.expectEqualStrings("@id|@title|@date", result.format);
    try testing.expect(result.sort_spec != null);
    try testing.expectEqualStrings("asc:@id", result.sort_spec.?);
}

test "parseIndexSpec: without sort spec" {
    const result = parseIndexSpec("@id|@title|@date");
    try testing.expectEqualStrings("@id|@title|@date", result.format);
    try testing.expect(result.sort_spec == null);
}

test "getDefaultSortConfig: with id" {
    var docs = [_]DocumentMeta{
        .{ .filename = "a.md", .id = "001", .title = "", .date = "", .name = "", .status = "", .mtime = 0 },
    };
    const config = getDefaultSortConfig(&docs);
    try testing.expectEqualStrings("@id", config.field);
    try testing.expectEqual(SortOrder.asc, config.order);
}

test "getDefaultSortConfig: with date only" {
    var docs = [_]DocumentMeta{
        .{ .filename = "a.md", .id = "", .title = "", .date = "2026-01-18", .name = "", .status = "", .mtime = 0 },
    };
    const config = getDefaultSortConfig(&docs);
    try testing.expectEqualStrings("@date", config.field);
    try testing.expectEqual(SortOrder.desc, config.order);
}

test "getDefaultSortConfig: no id or date" {
    var docs = [_]DocumentMeta{
        .{ .filename = "a.md", .id = "", .title = "", .date = "", .name = "", .status = "", .mtime = 0 },
    };
    const config = getDefaultSortConfig(&docs);
    try testing.expectEqualStrings("@mtime", config.field);
    try testing.expectEqual(SortOrder.desc, config.order);
}

test "sortDocuments: by id ascending" {
    var docs = [_]DocumentMeta{
        .{ .filename = "b.md", .id = "002", .title = "B", .date = "", .name = "", .status = "", .mtime = 0 },
        .{ .filename = "a.md", .id = "001", .title = "A", .date = "", .name = "", .status = "", .mtime = 0 },
        .{ .filename = "c.md", .id = "003", .title = "C", .date = "", .name = "", .status = "", .mtime = 0 },
    };
    sortDocuments(&docs, .{ .field = "@id", .order = .asc });
    try testing.expectEqualStrings("001", docs[0].id);
    try testing.expectEqualStrings("002", docs[1].id);
    try testing.expectEqualStrings("003", docs[2].id);
}

test "sortDocuments: by date descending" {
    var docs = [_]DocumentMeta{
        .{ .filename = "a.md", .id = "", .title = "", .date = "2026-01-15", .name = "", .status = "", .mtime = 0 },
        .{ .filename = "b.md", .id = "", .title = "", .date = "2026-01-20", .name = "", .status = "", .mtime = 0 },
        .{ .filename = "c.md", .id = "", .title = "", .date = "2026-01-10", .name = "", .status = "", .mtime = 0 },
    };
    sortDocuments(&docs, .{ .field = "@date", .order = .desc });
    try testing.expectEqualStrings("2026-01-20", docs[0].date);
    try testing.expectEqualStrings("2026-01-15", docs[1].date);
    try testing.expectEqualStrings("2026-01-10", docs[2].date);
}

test "sortDocuments: by mtime descending" {
    var docs = [_]DocumentMeta{
        .{ .filename = "a.md", .id = "", .title = "", .date = "", .name = "", .status = "", .mtime = 1000 },
        .{ .filename = "b.md", .id = "", .title = "", .date = "", .name = "", .status = "", .mtime = 3000 },
        .{ .filename = "c.md", .id = "", .title = "", .date = "", .name = "", .status = "", .mtime = 2000 },
    };
    sortDocuments(&docs, .{ .field = "@mtime", .order = .desc });
    try testing.expectEqual(@as(i128, 3000), docs[0].mtime);
    try testing.expectEqual(@as(i128, 2000), docs[1].mtime);
    try testing.expectEqual(@as(i128, 1000), docs[2].mtime);
}

test "extractSortConfigFromTemplate: with sort spec" {
    const config = extractSortConfigFromTemplate("# Index\n\n{{@index{@id|@title,asc:@id}}}\n");
    try testing.expect(config != null);
    try testing.expectEqualStrings("@id", config.?.field);
    try testing.expectEqual(SortOrder.asc, config.?.order);
}

test "extractSortConfigFromTemplate: without sort spec" {
    const config = extractSortConfigFromTemplate("# Index\n\n{{@index{@id|@title}}}\n");
    try testing.expect(config == null);
}

test "extractSortConfigFromTemplate: default format" {
    const config = extractSortConfigFromTemplate("# Index\n\n{{@index}}\n");
    try testing.expect(config == null);
}
