import { Parser, loadWasm } from "@janustack/css-selector-parser";
import { parse as fb55Parse } from "css-what";
import { bench, group, run } from "mitata";
import { selector } from "../examples/shared.ts";

const wasm = await loadWasm();
const parser = new Parser(wasm);

group("SVG Optimizer Comparison", () => {
    bench("Janustack CSS Selector Parser", () => {
        parser.parse(selector);
    });

    bench("CSS what", () => {
        fb55Parse(selector);
    });
});

run();
