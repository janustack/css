const std = @import("std");
const Combinator = @import("./combinator.zig").Combinator;

pub const Selector = union(enum) {
    // Example: a[target] { background-color: yellow; }
    attribute: AttributeSelector,

    // Example: .center { text-align: center; }
    class: ClassSelector,

    // Example: p { color: red; }
    element: ElementSelector,

    // Example: #para1 { text-align: center; }
    id: IdSelector,

    pseudo_class: PseudoClassSelector,
    pseudo_element: PseudoElementSelector,

    universal: UniversalSelector,

    combinator: Combinator,

    pub fn isCombinator(this: @This()) bool {
        return switch (this) {
            .combinator => true,
            else => false,
        };
    }

    pub fn jsonStringify(this: @This(), writer: anytype) !void {
        switch (this) {
            .attribute => |attribute| try writer.write(.{
                .type = "attribute",
                .name = attribute.name,
                .action = @tagName(attribute.action),
                .value = attribute.value,
                .namespace = attribute.namespace,
                .caseSensitivity = @tagName(attribute.case_sensitivity),
            }),
            .class => |class| try writer.write(.{
                .type = "class",
                .name = class.name,
            }),
            .element => |element| try writer.write(.{
                .type = "element",
                .name = element.name,
                .namespace = element.namespace,
            }),
            .id => |id| try writer.write(.{
                .type = "id",
                .name = id.name,
            }),
            .pseudo_class => |pc| try writer.write(.{
                .type = "pseudo-class",
                .name = pc.name,
                .argument = if (pc.argument) |arg| switch (arg) {
                    .value => |v| v,
                    else => null,
                } else null,
            }),
            .pseudo_element => |pe| try writer.write(.{
                .type = "pseudo-element",
                .name = pe.name,
                .argument = pe.argument,
            }),
            .universal => |universal| try writer.write(.{
                .type = "universal",
                .namespace = universal.namespace,
            }),
            .combinator => |c| switch (c) {
                .child => try writer.write(.{ .type = "child" }),
                .column => try writer.write(.{ .type = "column" }),
                .descendant => try writer.write(.{ .type = "descendant" }),
                .next_sibling => try writer.write(.{ .type = "next-sibling" }),
                .subsequent_sibling => try writer.write(.{ .type = "subsequent-sibling" }),
            },
        }
    }
};

pub const AttributeSelector = struct {
    name: []const u8,
    action: Action = .exists,
    value: []const u8 = "",
    case_sensitivity: CaseSensitivity,
    namespace: ?[]const u8 = null,

    pub const Action = enum(u8) {
        // Sign: *=
        // Syntax: [attribute*=value]
        // Example: [href*="w3schools"]
        // Result: Selects all elements with a href attribute value containing the substring "w3schools"
        substring,

        // Sign: ~=
        // Syntax: [attribute~=value]
        // Example: [title~="flower"]
        // Result: Selects all elements with a title attribute containing the word "flower"
        includes,

        // Sign: $=
        // Syntax: [attribute$=value]
        // Example [href$=".pdf"]
        // Result: Selects all elements with a href attribute value ends with ".pdf"
        suffix,

        // Sign: =
        // Syntax: [attribute=value]
        // Example: [lang="it"]
        // Result: Selects all elements with lang="it"
        equals,

        // Syntax: [attribute]
        // Example: [lang]
        // Result: Selects all elements with a lang attribute
        exists,

        // Sign: |=
        // Syntax: [attribute|=value]
        // Example: [lang|="en"]
        // Result: Selects all elements with a lang attribute value equal to "en" or starting with "en-"
        hyphen,

        // Sign ^=
        // Syntax: [attribute^=value]
        // Example: [href^="https"]
        // Result: Selects all elements with a href attribute value that begins with "https"
        prefix,
    };

    pub const CaseSensitivity = enum(u8) {
        sensitive,
        unknown,
        ignore,
        quirks,
    };
};

pub const ClassSelector = struct {
    name: []const u8,
};

pub const ElementSelector = struct {
    name: []const u8,
    namespace: ?[]const u8,
};

pub const IdSelector = struct {
    name: []const u8,
};

pub const PseudoClassSelector = struct {
    name: []const u8,
    argument: ?Argument,

    pub const Argument = union(enum) {
        selectors: [][]Selector,
        value: []const u8,
    };
};

pub const PseudoElementSelector = struct {
    name: []const u8,
    argument: ?[]const u8,
};

pub const UniversalSelector = struct {
    namespace: ?[]const u8,
};
