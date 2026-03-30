import { Parser, loadWasm } from "@janustack/css-selector-parser";
import { selector } from "./shared.ts";

const wasm = await loadWasm();
const parser = new Parser(wasm);

const ast = parser.parse(selector);
// const ast = parse("div#main.content > ul li.active");

console.log(ast);
