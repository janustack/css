// main.zig
const std = @import("std");
const cssSelectorParser = @import("parser.zig");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // const selector = "div#main.content > ul li.active";

    const selector = "article#main.content.app-shell[data-env^=\"prod\"][data-build$=\"2026\"][lang|=\"en\"][data-role*=\"dashboard\" i]:not(.is-disabled):has(section#hero.banner[data-theme=\"dark\"] > h1.title::before):is(.layout--wide, .layout--fluid):where(nav.top-nav > ul.menu > li.item.active > a[href^=\"https://\"]):is(div.card.featured[data-kind~=\"primary\"]):host-context(body.theme-dark) > main.container > section.grid > div.row > div.col-12 + div.col-6 ~ div.col-6 > form#signup.form[action*=\"/subscribe\"] > fieldset.group > label.field > input[type=\"email\"][name=\"email\"][placeholder*=\"@\" i] + span.hint::after, aside.sidebar[data-sticky=\"true\"] > ul.links > li.link-item > a.link[href$=\".pdf\" i]::after, footer#site-footer.footer[data-version=\"v1\"] > div.inner > p.note";

    var parser: cssSelectorParser.Parser = .init(allocator);
    var parsed = try parser.parse(selector);
    defer parsed.deinit();

    try stdout.print("{f}\n", .{std.json.fmt(parsed.subselects, .{ .whitespace = .indent_2 })});

    try stdout.flush();
}
