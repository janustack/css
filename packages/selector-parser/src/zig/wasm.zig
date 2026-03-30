const std = @import("std");
const cssSelectorParser = @import("parser.zig");
const selector = @import("selector.zig");

var buffer: [2 * 1024 * 1024]u8 = undefined;
var out_len: u32 = 0;

export fn getOutPtr() [*]u8 {
    return &buffer;
}

export fn getOutLen() u32 {
    return out_len;
}

export fn parse(ptr: [*]const u8, len: u32) u32 {
    const input = ptr[0..len];

    var parser: cssSelectorParser.Parser = .init(std.heap.wasm_allocator);
    var parsed = parser.parse(input) catch return 1;
    defer parsed.deinit();

    var fbs = std.Io.fixedBufferStream(&buffer);
    fbs.writer().print("{f}", .{std.json.fmt(parsed.subselects, .{})}) catch return 2;

    out_len = @intCast(fbs.pos);
    return 0;
}

export fn alloc(len: usize) ?[*]u8 {
    const slice = std.heap.wasm_allocator.alloc(u8, len) catch return null;
    return slice.ptr;
}

export fn free(ptr: [*]u8, len: usize) void {
    std.heap.wasm_allocator.free(ptr[0..len]);
}
