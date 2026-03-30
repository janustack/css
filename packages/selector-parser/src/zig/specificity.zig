const std = @import("std");

pub const Specificity = struct {
    element_selectors: u32 = 0,
    id_selectors: u32 = 0,
    pseudo_element_selectors: u32 = 0,

    pub fn add(a: *@This(), b: *@This()) void {

    }
};
