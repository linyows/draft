const std = @import("std");
const mem = std.mem;

pub const DocumentMeta = struct {
    filename: []const u8,
    id: []const u8,
    title: []const u8,
    date: []const u8,
    name: []const u8,
    status: []const u8,
};

pub fn extractDocumentMeta(allocator: mem.Allocator, filename: []const u8, content: []const u8) !DocumentMeta {
    var meta = DocumentMeta{
        .filename = try allocator.dupe(u8, filename),
        .id = try allocator.dupe(u8, ""),
        .title = try allocator.dupe(u8, ""),
        .date = try allocator.dupe(u8, ""),
        .name = try allocator.dupe(u8, ""),
        .status = try allocator.dupe(u8, ""),
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

pub fn expandIndex(allocator: mem.Allocator, template: []const u8, docs: []const DocumentMeta) ![]const u8 {
    var result = try allocator.dupe(u8, template);

    // Find {{@index}} or {{@index{...}}}
    const index_start = "{{@index";
    if (mem.indexOf(u8, result, index_start)) |start_idx| {
        const after_start = result[start_idx + index_start.len ..];

        var format: []const u8 = "@title|@date|@name"; // default format
        var end_idx: usize = 0;

        if (after_start.len > 0 and after_start[0] == '{') {
            // Custom format: {{@index{@id|@title|@status}}}
            if (mem.indexOf(u8, after_start, "}}}")) |close_idx| {
                format = after_start[1..close_idx];
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

    const meta = try extractDocumentMeta(allocator, "001-auth.md", content);
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
}

test "extractDocumentMeta: id from filename" {
    const allocator = testing.allocator;
    const content = "# My Title\n\nSome content";

    const meta = try extractDocumentMeta(allocator, "042-my-doc.md", content);
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
        },
    };

    const result = try expandIndex(allocator, template, &docs);
    defer allocator.free(result);

    try testing.expect(mem.indexOf(u8, result, "| ID | Title | Status |") != null);
    try testing.expect(mem.indexOf(u8, result, "[001](./001-test.md)") != null);
    try testing.expect(mem.indexOf(u8, result, "Accepted") != null);
}
