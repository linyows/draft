const std = @import("std");
const mem = std.mem;

pub fn replaceVariables(allocator: mem.Allocator, content: []const u8, title: []const u8, today: []const u8, username: []const u8, id: []const u8) ![]const u8 {
    var result: []const u8 = try allocator.dupe(u8, content);

    // Replace {{@title{format}}} before {{@title}} so formatted variants are handled first
    result = try replaceTitleWithFormat(allocator, result, title);
    result = try replaceAll(allocator, result, "{{@title}}", title);
    result = try replaceAll(allocator, result, "{{@today}}", today);
    result = try replaceAll(allocator, result, "{{@date}}", today);
    result = try replaceAll(allocator, result, "{{@name}}", username);
    result = try replaceIdWithFormat(allocator, result, id);

    return result;
}

pub fn replaceTitleWithFormat(allocator: mem.Allocator, input: []const u8, title: []const u8) ![]const u8 {
    var result: []const u8 = input;

    // Replace {{@title{format}}} patterns (e.g., {{@title{snake}}}, {{@title{kebab}}})
    var pos: usize = 0;
    while (pos < result.len) {
        if (mem.indexOf(u8, result[pos..], "{{@title{")) |start| {
            const abs_start = pos + start;
            const after_prefix = result[abs_start + 9 ..];

            if (mem.indexOf(u8, after_prefix, "}}}")) |end| {
                const format_str = after_prefix[0..end];
                const transformed = try transformTitle(allocator, title, format_str) orelse {
                    // Unknown format, skip this pattern
                    pos = abs_start + 9 + end + 3;
                    continue;
                };
                defer allocator.free(transformed);

                const pattern_end = abs_start + 9 + end + 3;
                const new_len = abs_start + transformed.len + (result.len - pattern_end);
                var new_result = try allocator.alloc(u8, new_len);

                @memcpy(new_result[0..abs_start], result[0..abs_start]);
                @memcpy(new_result[abs_start .. abs_start + transformed.len], transformed);
                @memcpy(new_result[abs_start + transformed.len ..], result[pattern_end..]);

                allocator.free(result);
                result = new_result;
                pos = abs_start + transformed.len;
                continue;
            }
        }
        break;
    }

    return result;
}

fn transformTitle(allocator: mem.Allocator, title: []const u8, format: []const u8) !?[]const u8 {
    if (mem.eql(u8, format, "snake")) {
        return try toSnakeCase(allocator, title);
    } else if (mem.eql(u8, format, "kebab")) {
        return try toKebabCase(allocator, title);
    } else if (mem.eql(u8, format, "lower")) {
        return try toLower(allocator, title);
    } else if (mem.eql(u8, format, "camel")) {
        return try toCamelCase(allocator, title);
    } else if (mem.eql(u8, format, "pascal")) {
        return try toPascalCase(allocator, title);
    }
    return null;
}

fn toLower(allocator: mem.Allocator, input: []const u8) ![]const u8 {
    var result = try allocator.alloc(u8, input.len);
    for (input, 0..) |c, i| {
        result[i] = if (c >= 'A' and c <= 'Z') c + 32 else c;
    }
    return result;
}

fn toSnakeCase(allocator: mem.Allocator, input: []const u8) ![]const u8 {
    return try toSeparatedLowerCase(allocator, input, '_');
}

fn toKebabCase(allocator: mem.Allocator, input: []const u8) ![]const u8 {
    return try toSeparatedLowerCase(allocator, input, '-');
}

fn toSeparatedLowerCase(allocator: mem.Allocator, input: []const u8, separator: u8) ![]const u8 {
    // First pass: calculate output length
    var len: usize = 0;
    var prev_was_separator = true; // treat start as separator to avoid leading separator
    for (input, 0..) |c, i| {
        if (c == ' ' or c == '-' or c == '_') {
            if (!prev_was_separator) {
                len += 1;
                prev_was_separator = true;
            }
        } else if (c >= 'A' and c <= 'Z') {
            // Insert separator before uppercase if not at boundary
            if (!prev_was_separator and i > 0) {
                // Check if previous char was lowercase (camelCase boundary)
                const prev = input[i - 1];
                if (prev >= 'a' and prev <= 'z') {
                    len += 1;
                }
            }
            len += 1;
            prev_was_separator = false;
        } else {
            len += 1;
            prev_was_separator = false;
        }
    }

    var result = try allocator.alloc(u8, len);
    var write_pos: usize = 0;
    prev_was_separator = true;
    for (input, 0..) |c, i| {
        if (c == ' ' or c == '-' or c == '_') {
            if (!prev_was_separator) {
                result[write_pos] = separator;
                write_pos += 1;
                prev_was_separator = true;
            }
        } else if (c >= 'A' and c <= 'Z') {
            if (!prev_was_separator and i > 0) {
                const prev = input[i - 1];
                if (prev >= 'a' and prev <= 'z') {
                    result[write_pos] = separator;
                    write_pos += 1;
                }
            }
            result[write_pos] = c + 32;
            write_pos += 1;
            prev_was_separator = false;
        } else {
            result[write_pos] = c;
            write_pos += 1;
            prev_was_separator = false;
        }
    }

    return result[0..write_pos];
}

fn toCamelCase(allocator: mem.Allocator, input: []const u8) ![]const u8 {
    return try toCamelOrPascalCase(allocator, input, false);
}

fn toPascalCase(allocator: mem.Allocator, input: []const u8) ![]const u8 {
    return try toCamelOrPascalCase(allocator, input, true);
}

fn toCamelOrPascalCase(allocator: mem.Allocator, input: []const u8, capitalize_first: bool) ![]const u8 {
    // First pass: calculate output length (remove spaces/separators)
    var len: usize = 0;
    for (input) |c| {
        if (c != ' ' and c != '-' and c != '_') {
            len += 1;
        }
    }

    var result = try allocator.alloc(u8, len);
    var write_pos: usize = 0;
    var capitalize_next = capitalize_first;
    var is_first = true;
    for (input) |c| {
        if (c == ' ' or c == '-' or c == '_') {
            capitalize_next = true;
        } else {
            if (capitalize_next and !is_first) {
                result[write_pos] = if (c >= 'a' and c <= 'z') c - 32 else c;
            } else if (is_first) {
                if (capitalize_first) {
                    result[write_pos] = if (c >= 'a' and c <= 'z') c - 32 else c;
                } else {
                    result[write_pos] = if (c >= 'A' and c <= 'Z') c + 32 else c;
                }
                is_first = false;
            } else {
                result[write_pos] = if (c >= 'A' and c <= 'Z') c + 32 else c;
            }
            write_pos += 1;
            capitalize_next = false;
        }
    }

    return result[0..write_pos];
}

pub fn replaceIdWithFormat(allocator: mem.Allocator, input: []const u8, id: []const u8) ![]const u8 {
    var result: []const u8 = input;
    const id_num = std.fmt.parseInt(u32, id, 10) catch 0;

    // Replace {{@id{N}}} format first (e.g., {{@id{4}}} -> 0001)
    var pos: usize = 0;
    while (pos < result.len) {
        if (mem.indexOf(u8, result[pos..], "{{@id{")) |start| {
            const abs_start = pos + start;
            const after_prefix = result[abs_start + 6 ..];

            if (mem.indexOf(u8, after_prefix, "}}}")) |end| {
                const width_str = after_prefix[0..end];
                const width = std.fmt.parseInt(u8, width_str, 10) catch 3;

                const formatted_id = try formatId(allocator, id_num, width);
                defer allocator.free(formatted_id);

                const pattern_end = abs_start + 6 + end + 3;
                const new_len = abs_start + formatted_id.len + (result.len - pattern_end);
                var new_result = try allocator.alloc(u8, new_len);

                @memcpy(new_result[0..abs_start], result[0..abs_start]);
                @memcpy(new_result[abs_start .. abs_start + formatted_id.len], formatted_id);
                @memcpy(new_result[abs_start + formatted_id.len ..], result[pattern_end..]);

                allocator.free(result);
                result = new_result;
                pos = abs_start + formatted_id.len;
                continue;
            }
        }
        break;
    }

    // Replace {{@id}} with default 3 digits
    const default_id = try formatId(allocator, id_num, 3);
    defer allocator.free(default_id);

    // replaceAll takes ownership of result:
    // - If no match found, returns result as-is
    // - If match found, frees result and returns new allocation
    result = try replaceAll(allocator, result, "{{@id}}", default_id);

    return result;
}

pub fn formatId(allocator: mem.Allocator, id: u32, width: u8) ![]const u8 {
    return switch (width) {
        1 => try std.fmt.allocPrint(allocator, "{d:0>1}", .{id}),
        2 => try std.fmt.allocPrint(allocator, "{d:0>2}", .{id}),
        3 => try std.fmt.allocPrint(allocator, "{d:0>3}", .{id}),
        4 => try std.fmt.allocPrint(allocator, "{d:0>4}", .{id}),
        5 => try std.fmt.allocPrint(allocator, "{d:0>5}", .{id}),
        6 => try std.fmt.allocPrint(allocator, "{d:0>6}", .{id}),
        else => try std.fmt.allocPrint(allocator, "{d:0>3}", .{id}),
    };
}

pub fn replaceAll(allocator: mem.Allocator, input: []const u8, needle: []const u8, replacement: []const u8) ![]const u8 {
    var count: usize = 0;
    var pos: usize = 0;
    while (pos < input.len) {
        if (mem.indexOf(u8, input[pos..], needle)) |idx| {
            count += 1;
            pos += idx + needle.len;
        } else {
            break;
        }
    }

    if (count == 0) {
        return input;
    }

    const new_len = input.len - (count * needle.len) + (count * replacement.len);
    var result = try allocator.alloc(u8, new_len);

    var write_pos: usize = 0;
    var read_pos: usize = 0;
    while (read_pos < input.len) {
        if (mem.indexOf(u8, input[read_pos..], needle)) |idx| {
            @memcpy(result[write_pos .. write_pos + idx], input[read_pos .. read_pos + idx]);
            write_pos += idx;
            @memcpy(result[write_pos .. write_pos + replacement.len], replacement);
            write_pos += replacement.len;
            read_pos += idx + needle.len;
        } else {
            @memcpy(result[write_pos..], input[read_pos..]);
            break;
        }
    }

    allocator.free(input);

    return result;
}

// =============================================================================
// Tests
// =============================================================================

const testing = std.testing;

test "replaceAll: single replacement" {
    const allocator = testing.allocator;
    const input = try allocator.dupe(u8, "Hello, {{@name}}!");
    const result = try replaceAll(allocator, input, "{{@name}}", "World");
    defer allocator.free(result);

    try testing.expectEqualStrings("Hello, World!", result);
}

test "replaceAll: multiple replacements" {
    const allocator = testing.allocator;
    const input = try allocator.dupe(u8, "{{@x}} and {{@x}} and {{@x}}");
    const result = try replaceAll(allocator, input, "{{@x}}", "Y");
    defer allocator.free(result);

    try testing.expectEqualStrings("Y and Y and Y", result);
}

test "replaceAll: no match returns input" {
    const allocator = testing.allocator;
    const input = try allocator.dupe(u8, "Hello, World!");
    const result = try replaceAll(allocator, input, "{{@name}}", "Test");
    defer allocator.free(result);

    try testing.expectEqualStrings("Hello, World!", result);
}

test "replaceAll: empty replacement" {
    const allocator = testing.allocator;
    const input = try allocator.dupe(u8, "Hello, {{@name}}!");
    const result = try replaceAll(allocator, input, "{{@name}}", "");
    defer allocator.free(result);

    try testing.expectEqualStrings("Hello, !", result);
}

test "replaceAll: longer replacement" {
    const allocator = testing.allocator;
    const input = try allocator.dupe(u8, "Hi {{@x}}");
    const result = try replaceAll(allocator, input, "{{@x}}", "LongerString");
    defer allocator.free(result);

    try testing.expectEqualStrings("Hi LongerString", result);
}

test "replaceVariables: all variables" {
    const allocator = testing.allocator;
    const template = "# {{@title}}\n- Date: {{@date}}\n- Today: {{@today}}\n- Author: {{@name}}\n- ID: {{@id}}";
    const result = try replaceVariables(allocator, template, "Test Title", "2026-01-18", "testuser", "042");
    defer allocator.free(result);

    try testing.expectEqualStrings("# Test Title\n- Date: 2026-01-18\n- Today: 2026-01-18\n- Author: testuser\n- ID: 042", result);
}

test "replaceVariables: partial variables" {
    const allocator = testing.allocator;
    const template = "Title: {{@title}}";
    const result = try replaceVariables(allocator, template, "My Doc", "2026-01-18", "user", "001");
    defer allocator.free(result);

    try testing.expectEqualStrings("Title: My Doc", result);
}

test "replaceVariables: no variables" {
    const allocator = testing.allocator;
    const template = "Plain text without variables";
    const result = try replaceVariables(allocator, template, "Title", "2026-01-18", "user", "001");
    defer allocator.free(result);

    try testing.expectEqualStrings("Plain text without variables", result);
}

test "replaceVariables: multibyte title" {
    const allocator = testing.allocator;
    const template = "# {{@title}}\n\nAuthor: {{@name}}";
    const result = try replaceVariables(allocator, template, "Authentication System Design", "2026-01-18", "linyows", "001");
    defer allocator.free(result);

    try testing.expectEqualStrings("# Authentication System Design\n\nAuthor: linyows", result);
}

test "replaceIdWithFormat: default 3 digits" {
    const allocator = testing.allocator;
    const input = try allocator.dupe(u8, "ID: {{@id}}");
    const result = try replaceIdWithFormat(allocator, input, "1");
    defer allocator.free(result);

    try testing.expectEqualStrings("ID: 001", result);
}

test "replaceIdWithFormat: custom 4 digits" {
    const allocator = testing.allocator;
    const input = try allocator.dupe(u8, "ID: {{@id{4}}}");
    const result = try replaceIdWithFormat(allocator, input, "1");
    defer allocator.free(result);

    try testing.expectEqualStrings("ID: 0001", result);
}

test "replaceIdWithFormat: custom 2 digits" {
    const allocator = testing.allocator;
    const input = try allocator.dupe(u8, "{{@id{2}}}-{{@title}}");
    const result = try replaceIdWithFormat(allocator, input, "5");
    defer allocator.free(result);

    try testing.expectEqualStrings("05-{{@title}}", result);
}

test "formatId: various widths" {
    const allocator = testing.allocator;

    const id1 = try formatId(allocator, 1, 1);
    defer allocator.free(id1);
    try testing.expectEqualStrings("1", id1);

    const id2 = try formatId(allocator, 1, 2);
    defer allocator.free(id2);
    try testing.expectEqualStrings("01", id2);

    const id4 = try formatId(allocator, 42, 4);
    defer allocator.free(id4);
    try testing.expectEqualStrings("0042", id4);

    const id6 = try formatId(allocator, 123, 6);
    defer allocator.free(id6);
    try testing.expectEqualStrings("000123", id6);
}

test "toSnakeCase: spaces to underscores" {
    const allocator = testing.allocator;
    const result = try toSnakeCase(allocator, "API Design Review");
    defer allocator.free(result);
    try testing.expectEqualStrings("api_design_review", result);
}

test "toKebabCase: spaces to hyphens" {
    const allocator = testing.allocator;
    const result = try toKebabCase(allocator, "API Design Review");
    defer allocator.free(result);
    try testing.expectEqualStrings("api-design-review", result);
}

test "toLower: uppercase to lowercase" {
    const allocator = testing.allocator;
    const result = try toLower(allocator, "API Design Review");
    defer allocator.free(result);
    try testing.expectEqualStrings("api design review", result);
}

test "toCamelCase: words to camelCase" {
    const allocator = testing.allocator;
    const result = try toCamelCase(allocator, "API Design Review");
    defer allocator.free(result);
    try testing.expectEqualStrings("apiDesignReview", result);
}

test "toPascalCase: words to PascalCase" {
    const allocator = testing.allocator;
    const result = try toPascalCase(allocator, "API Design Review");
    defer allocator.free(result);
    try testing.expectEqualStrings("ApiDesignReview", result);
}

test "toSnakeCase: camelCase input" {
    const allocator = testing.allocator;
    const result = try toSnakeCase(allocator, "camelCaseInput");
    defer allocator.free(result);
    try testing.expectEqualStrings("camel_case_input", result);
}

test "toKebabCase: multiple spaces and mixed separators" {
    const allocator = testing.allocator;
    const result = try toKebabCase(allocator, "Hello  World-Test_Case");
    defer allocator.free(result);
    try testing.expectEqualStrings("hello-world-test-case", result);
}

test "replaceTitleWithFormat: snake in template" {
    const allocator = testing.allocator;
    const input = try allocator.dupe(u8, "{{@id{4}}}-{{@title{snake}}}.md");
    const result = try replaceTitleWithFormat(allocator, input, "Authentication System");
    defer allocator.free(result);
    try testing.expectEqualStrings("{{@id{4}}}-authentication_system.md", result);
}

test "replaceTitleWithFormat: kebab in template" {
    const allocator = testing.allocator;
    const input = try allocator.dupe(u8, "{{@date}}-{{@title{kebab}}}.md");
    const result = try replaceTitleWithFormat(allocator, input, "API Design Review");
    defer allocator.free(result);
    try testing.expectEqualStrings("{{@date}}-api-design-review.md", result);
}

test "replaceVariables: title with snake format in filename" {
    const allocator = testing.allocator;
    const template = "{{@id{4}}}-{{@title{snake}}}.md";
    const result = try replaceVariables(allocator, template, "Authentication System", "2026-01-18", "user", "1");
    defer allocator.free(result);
    try testing.expectEqualStrings("0001-authentication_system.md", result);
}

test "replaceVariables: title with kebab format and plain title" {
    const allocator = testing.allocator;
    const template = "# {{@title}}\nFile: {{@title{kebab}}}.md";
    const result = try replaceVariables(allocator, template, "API Design Review", "2026-01-18", "user", "1");
    defer allocator.free(result);
    try testing.expectEqualStrings("# API Design Review\nFile: api-design-review.md", result);
}
