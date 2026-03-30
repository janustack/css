import { createParser } from 'css-selector-parser';
import { selector } from "./shared.ts";

const parse = createParser();
const parsed = parse(selector);
console.log(parsed);
