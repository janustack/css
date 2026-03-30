pub const Combinator = enum(u8) {
    // Sign: >
    // Example: div > p
    // Result: Selects every <p> element that are direct children of a <div> element
    child,

    // Sign: ||
    column,

    // Sign: (whitespace)
    // Example: div p
    // Result: Selects all <p> elements inside <div> elements
    descendant,

    // Sign: +
    // Example: div + p
    // Result: Selects the first <p> element that is placed immediately after <div> elements
    next_sibling,

    // Sign: ~
    // Example: p ~ ul
    // Result: Selects all <ul> elements that are preceded by a <p> element
    subsequent_sibling,
};
