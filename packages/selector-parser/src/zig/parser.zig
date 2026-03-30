// parser.zig
const std = @import("std");
const selector = @import("selector.zig");
const Combinator = @import("combinator.zig").Combinator;

const Selector = selector.Selector;
const AttributeSelector = selector.AttributeSelector;

const PseudoClasses = struct {
    const selector_list_argument = std.StaticStringMap(void).initComptime(.{
        .{ "has", {} },
        .{ "host", {} }, // Takes a single compound selector as its parameter.
        .{ "is", {} },
        .{ "not", {} },
        .{ "where", {} },
    });

    const identifier_argument = std.StaticStringMap(void).initComptime(.{
        .{ "dir", {} },
        .{ "heading", {} },
        .{ "lang", {} },
        .{ "state", {} },
    });
};

const ParseError = error{
    UnmatchedSelector,
    ExpectedName,
    ParenthesisNotMatched,
    SuccessiveTraversals,
    EmptySubselector,
    UnexpectedToken,
    AttributeValueUnterminated,
    AttributeSelectorUnterminated,
    ExpectedEquals,
    CommentNotTerminated,
    PseudoCannotBeQuoted,
    MissingClosingParenthesis,
    OutOfMemory,
};

pub const Parsed = struct {
    arena: std.heap.ArenaAllocator,
    subselects: [][]Selector,

    pub fn deinit(this: *@This()) void {
        this.arena.deinit();
    }
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    selector: []const u8 = "",
    index: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Parser {
        return .{
            .allocator = allocator,
        };
    }

    pub fn parse(this: *@This(), sel: []const u8) ParseError!Parsed {
        this.selector = sel;
        this.index = 0;

        var arena: std.heap.ArenaAllocator = .init(this.allocator);
        errdefer arena.deinit();
        const allocator = arena.allocator();

        var subselects: std.ArrayList([]Selector) = .empty;
        defer subselects.deinit(allocator);

        const end_index = try this.parseSelector(allocator, &subselects, 0);

        if (end_index < this.selector.len) {
            return ParseError.UnmatchedSelector;
        }

        return .{
            .arena = arena,
            .subselects = try subselects.toOwnedSlice(allocator),
        };
    }

    fn parseSelector(
        this: *@This(),
        allocator: std.mem.Allocator,
        subselects: *std.ArrayList([]Selector),
        start: usize,
    ) ParseError!usize {
        var tokens: std.ArrayList(Selector) = .empty;
        defer tokens.deinit(allocator);

        this.index = start;

        this.stripWhitespace();

        if (this.index >= this.selector.len) {
            return this.index;
        }

        while (this.index < this.selector.len) {
            const first_char = this.selector[this.index];

            switch (first_char) {
                ')' => {
                    // Do not consume ')'. Caller will handle it.
                    try finalizeSubselector(allocator, subselects, &tokens);
                    return this.index;
                },
                ' ',
                '\t',
                '\n',
                '\x0C', // form feed
                '\r',
                => {
                                        var is_descendant = false;
                                        if (tokens.items.len > 0) {
                                            const last = tokens.items[tokens.items.len - 1];
                                            is_descendant = last.isCombinator() and last.combinator == .descendant;
                                        }
                                        if (tokens.items.len == 0 or !is_descendant) {
                                            try ensureNotTraversal(tokens.items);
                                            try tokens.append(allocator, .{ .combinator = .descendant });
                                        }
                                        this.index += 1;
                                        this.stripWhitespace();
                },
                '>' => {
                    try addTraversal(allocator, &tokens, .child);
                    this.index += 1;
                    this.stripWhitespace();
                },
                '~' => {
                    try addTraversal(allocator, &tokens, .subsequent_sibling);
                    this.index += 1;
                    this.stripWhitespace();
                },
                '+' => {
                    try addTraversal(allocator, &tokens, .next_sibling);
                    this.index += 1;
                    this.stripWhitespace();
                },
                '.' => {
                    const name = try this.getName(allocator, 1);
                    try tokens.append(allocator, .{ .class = .{
                        .name = name,
                    } });
                },
                '#' => {
                    const name = try this.getName(allocator, 1);
                    try tokens.append(allocator, .{ .id = .{
                        .name = name,
                    } });
                },
                '[' => {
                    this.index += 1;
                    this.stripWhitespace();

                    var name: []const u8 = undefined;
                    var namespace: ?[]const u8 = null;

                    if (this.index < this.selector.len and this.selector[this.index] == '|') {
                        name = try this.getName(allocator, 1);
                    } else if (this.selector[this.index..].len >= 2 and
                        std.mem.eql(u8, this.selector[this.index .. this.index + 2], "*|"))
                    {
                        namespace = "*";
                        name = try this.getName(allocator, 2);
                    } else {
                        name = try this.getName(allocator, 0);
                        if (this.index < this.selector.len and
                            this.selector[this.index] == '|' and
                            (this.index + 1 >= this.selector.len or
                                this.selector[this.index + 1] != '='))
                        {
                            namespace = name;
                            name = try this.getName(allocator, 1);
                        }
                    }

                    this.stripWhitespace();

                    var action: AttributeSelector.Action = .exists;
                    if (this.index < this.selector.len) {
                        const c = this.selector[this.index];

                        const maybe_action: ?AttributeSelector.Action = switch (c) {
                            '|' => .hyphen,
                            '~' => .includes,
                            '^' => .prefix,
                            '*' => .substring,
                            '$' => .suffix,
                            else => null,
                        };

                        if (maybe_action) |a| {
                            action = a;
                            if (this.index + 1 >= this.selector.len or
                                this.selector[this.index + 1] != '=')
                            {
                                return ParseError.ExpectedEquals;
                            }
                            this.index += 2;
                            this.stripWhitespace();
                        } else if (this.selector[this.index] == '=') {
                            action = .equals;
                            this.index += 1;
                            this.stripWhitespace();
                        }
                    }

                    var value: []const u8 = "";
                    var case_sensitivity: AttributeSelector.CaseSensitivity = .unknown;

                    if (action != .exists) {
                        if (this.index < this.selector.len and
                            isQuote(this.selector[this.index]))
                        {
                            const quote = this.selector[this.index];
                            this.index += 1;
                            const section_start = this.index;
                            while (this.index < this.selector.len and
                                this.selector[this.index] != quote)
                            {
                                this.index += if (this.selector[this.index] == '\\') 2 else 1;
                            }
                            if (this.index >= this.selector.len or this.selector[this.index] != quote) {
                                return ParseError.AttributeValueUnterminated;
                            }
                            value = try unescapeCSS(allocator, this.selector[section_start..this.index]);
                            this.index += 1;
                        } else {
                            const value_start = this.index;
                            while (this.index < this.selector.len and
                                !std.ascii.isWhitespace(this.selector[this.index]) and
                                this.selector[this.index] != ']')
                            {
                                this.index += if (this.selector[this.index] == '\\') 2 else 1;
                            }
                            value = try unescapeCSS(allocator, this.selector[value_start..this.index]);
                        }

                        this.stripWhitespace();

                        if (this.index < this.selector.len) {
                            switch (this.selector[this.index] | 0x20) {
                                'i' => {
                                    case_sensitivity = .ignore;
                                    this.index += 1;
                                    this.stripWhitespace();
                                },
                                's' => {
                                    case_sensitivity = .sensitive;
                                    this.index += 1;
                                    this.stripWhitespace();
                                },
                                else => {},
                            }
                        }
                    }

                    if (this.index >= this.selector.len or
                        this.selector[this.index] != ']')
                    {
                        return ParseError.AttributeSelectorUnterminated;
                    }
                    this.index += 1;

                    try tokens.append(allocator, .{ .attribute = .{
                        .name = name,
                        .action = action,
                        .value = value,
                        .namespace = namespace,
                        .case_sensitivity = case_sensitivity,
                    } });
                },
                ':' => {
                    if (this.index + 1 < this.selector.len and
                        this.selector[this.index + 1] == ':')
                    {
                        const name = try this.getName(allocator, 2);
                        const lower_name = try std.ascii.allocLowerString(allocator, name);
                        var data: ?[]const u8 = null;
                        if (this.index < this.selector.len and
                            this.selector[this.index] == '(')
                        {
                            data = try this.readValueWithParenthesis(allocator);
                        }
                        try tokens.append(allocator, .{ .pseudo_element = .{
                            .name = lower_name,
                            .argument = data,
                        } });
                        continue;
                    }

                    const name = try this.getName(allocator, 1);
                    const lower_name = try std.ascii.allocLowerString(allocator, name);

                    var data: ?selector.PseudoClassSelector.Argument = null;

                    if (this.index < this.selector.len and
                        this.selector[this.index] == '(')
                    {
                        if (PseudoClasses.selector_list_argument.get(lower_name) != null) {
                            if (this.index + 1 < this.selector.len and
                                isQuote(this.selector[this.index + 1]))
                            {
                                return ParseError.PseudoCannotBeQuoted;
                            }

                            var inner: std.ArrayList([]Selector) = .empty;
                            defer inner.deinit(allocator);

                            this.index = try this.parseSelector(allocator, &inner, this.index + 1);

                            if (this.index >= this.selector.len or
                                this.selector[this.index] != ')')
                            {
                                return ParseError.MissingClosingParenthesis;
                            }
                            this.index += 1;
                            data = .{ .selectors = try inner.toOwnedSlice(allocator) };
                        } else {
                            var raw = try this.readValueWithParenthesis(allocator);

                            if (PseudoClasses.identifier_argument.get(lower_name) != null) {
                                if (raw.len >= 2) {
                                    const q = raw[0];
                                    if (raw[raw.len - 1] == q and isQuote(q)) {
                                        raw = raw[1 .. raw.len - 1];
                                    }
                                }
                            }

                            data = .{ .value = try unescapeCSS(allocator, raw) };
                        }
                    }

                    try tokens.append(allocator, .{ .pseudo_class = .{
                        .name = lower_name,
                        .argument = data,
                    } });
                },
                ',' => {
                    try finalizeSubselector(allocator, subselects, &tokens);
                    tokens.clearRetainingCapacity();
                    this.index += 1;
                    this.stripWhitespace();
                },
                else => {
                    // Comment
                    if (this.selector[this.index..].len >= 2 and
                        std.mem.eql(u8, this.selector[this.index .. this.index + 2], "/*"))
                    {
                        const end_idx = std.mem.indexOf(
                            u8,
                            this.selector[this.index + 2 ..],
                            "*/",
                        ) orelse return ParseError.CommentNotTerminated;
                        this.index = this.index + 2 + end_idx + 2;
                        if (tokens.items.len == 0) this.stripWhitespace();
                        continue;
                    }

                    var namespace: ?[]const u8 = null;
                    var name: []const u8 = undefined;

                    if (first_char == '*') {
                        this.index += 1;
                        name = "*";
                    } else if (first_char == '|') {
                        if (this.index + 1 < this.selector.len and
                            this.selector[this.index + 1] == '|')
                        {
                            try addTraversal(allocator, &tokens, .column);
                            this.index += 2;
                            this.stripWhitespace();
                            break;
                        }
                        name = "";
                    } else if (matchesNameStart(first_char)) {
                        name = try this.getName(allocator, 0);
                    } else {
                        return ParseError.UnexpectedToken;
                    }

                    if (this.index < this.selector.len and
                        this.selector[this.index] == '|' and
                        (this.index + 1 >= this.selector.len or
                            this.selector[this.index + 1] != '|'))
                    {
                        namespace = name;
                        if (this.index + 1 < this.selector.len and
                            this.selector[this.index + 1] == '*')
                        {
                            name = "*";
                            this.index += 2;
                        } else {
                            name = try this.getName(allocator, 1);
                        }
                    }

                    if (std.mem.eql(u8, name, "*")) {
                        try tokens.append(allocator, .{ .universal = .{ .namespace = namespace } });
                    } else {
                        try tokens.append(allocator, .{ .element = .{ .name = name, .namespace = namespace } });
                    }
                },
            }
        }

        try finalizeSubselector(allocator, subselects, &tokens);
        return this.index;
    }

    fn stripWhitespace(this: *@This()) void {
        while (this.index < this.selector.len and
            std.ascii.isWhitespace(this.selector[this.index]))
        {
            this.index += 1;
        }
    }

    fn getName(this: *@This(), allocator: std.mem.Allocator, offset: usize) ParseError![]const u8 {
        this.index += offset;
        const start = this.index;

        if (this.index >= this.selector.len) return ParseError.ExpectedName;

        // Handle backslash escape at start
        if (this.selector[this.index] == '\\') {
            this.index += 2;
        } else if (!matchesNameStart(this.selector[this.index])) {
            return ParseError.ExpectedName;
        } else {
            this.index += 1;
        }

        while (this.index < this.selector.len and
            matchesNameBody(this.selector[this.index]))
        {
            if (this.selector[this.index] == '\\') {
                this.index += 2;
            } else {
                this.index += 1;
            }
        }

        return try unescapeCSS(allocator, this.selector[start..this.index]);
    }

    fn readValueWithParenthesis(this: *@This(), allocator: std.mem.Allocator) ParseError![]const u8 {
        this.index += 1; // skip '('
        const start = this.index;
        var counter: usize = 1;

        while (this.index < this.selector.len) {
            switch (this.selector[this.index]) {
                '\\' => this.index += 2,
                '(' => {
                    counter += 1;
                    this.index += 1;
                },
                ')' => {
                    counter -= 1;
                    if (counter == 0) {
                        const result = try unescapeCSS(allocator, this.selector[start..this.index]);
                        this.index += 1;
                        return result;
                    }
                    this.index += 1;
                },
                else => this.index += 1,
            }
        }

        return ParseError.ParenthesisNotMatched;
    }
};

fn addTraversal(
    allocator: std.mem.Allocator,
    tokens: *std.ArrayList(Selector),
    combinator: Combinator,
) ParseError!void {
    if (tokens.items.len > 0) {
        const last = tokens.items[tokens.items.len - 1];
        // FIX: Proper usage of isCombinator
        if (last.isCombinator() and last.combinator == .descendant) {
            tokens.items[tokens.items.len - 1] = .{ .combinator = combinator };
            return;
        }
    }
    try ensureNotTraversal(tokens.items);
    try tokens.append(allocator, .{ .combinator = combinator });
}

fn finalizeSubselector(
    allocator: std.mem.Allocator,
    subselects: *std.ArrayList([]Selector),
    tokens: *std.ArrayList(Selector),
) ParseError!void {
    if (tokens.items.len > 0) {
        const last = tokens.items[tokens.items.len - 1];
        if (last.isCombinator() and last.combinator == .descendant) {
            _ = tokens.pop();
        }
    }
    if (tokens.items.len == 0) return ParseError.EmptySubselector;
    try subselects.append(allocator, try tokens.toOwnedSlice(allocator));
}

fn unescapeCSS(allocator: std.mem.Allocator, input: []const u8) ParseError![]const u8 {
    if (std.mem.indexOfScalar(u8, input, '\\') == null) {
        return input;
    }

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);

    var i: usize = 0;

    while (i < input.len) {
        if (input[i] != '\\') {
            try buf.append(allocator, input[i]);
            i += 1;
            continue;
        }

        i += 1;
        if (i >= input.len) break;

        // Try hex escape: \XXXXXX
        var hex_len: usize = 0;
        while (hex_len < 6 and i + hex_len < input.len and
            std.ascii.isHex(input[i + hex_len]))
        {
            hex_len += 1;
        }

        if (hex_len > 0) {
            const code_point = std.fmt.parseInt(u21, input[i .. i + hex_len], 16) catch {
                try buf.append(allocator, input[i]);
                i += 1;
                continue;
            };
            var encoded: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(code_point, &encoded) catch {
                i += hex_len;
                continue;
            };
            try buf.appendSlice(allocator, encoded[0..len]);
            i += hex_len;
            // Optional trailing whitespace after hex escape
            if (i < input.len and std.ascii.isWhitespace(input[i])) i += 1;
        } else {
            // Literal escape: \X → X
            try buf.append(allocator, input[i]);
            i += 1;
        }
    }

    return buf.toOwnedSlice(allocator);
}

fn isQuote(c: u8) bool {
    return c == '\'' or c == '"';
}

fn matchesNameStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_' or c == '-' or c > 0xB0;
}

fn matchesNameBody(c: u8) bool {
    return matchesNameStart(c) or std.ascii.isDigit(c);
}

fn ensureNotTraversal(tokens: []Selector) ParseError!void {
    if (tokens.len > 0 and tokens[tokens.len - 1].isCombinator()) {
        return ParseError.SuccessiveTraversals;
    }
}
