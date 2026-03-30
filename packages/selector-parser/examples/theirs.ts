import { parse } from "css-what";
import { selector } from "./shared.ts";

const ast = parse(selector);

console.log(ast);
