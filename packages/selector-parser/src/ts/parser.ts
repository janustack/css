import { SelectorParseError } from "./error.js";
import type { Selector, WasmExports } from "./types.js";
import { readOutput, withString } from "./utils.js";

export class Parser {
    private wasm: WasmExports;

    constructor(wasm: WasmExports) {
        this.wasm = wasm;
    }

    /**
     * Parses `selector` into a two-dimensional array of tokens.
     * The first dimension represents comma-separated selectors,
     * the second contains the tokens for each selector.
     *
     * @throws {SelectorParseError} on invalid input.
     *
     * @example
     * parser.parse("div, span.foo")
     * // → [[{type:"tag",name:"div",...}], [{type:"tag",...}, {type:"attribute",...}]]
     */
    public parse(selector: string): Selector[][] {
        const status = withString(this.wasm, selector, (ptr, len) =>
            this.wasm.parse(ptr, len),
        );

        const output = readOutput(this.wasm);

        if (status !== 0) {
            throw new SelectorParseError(output, selector);
        }

        return JSON.parse(output) as Selector[][];
    }
}
