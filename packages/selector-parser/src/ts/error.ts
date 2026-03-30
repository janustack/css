export class SelectorParseError extends Error {
	readonly selector: string;

	constructor(message: string, selector: string) {
		super(message);
		this.name = "SelectorParseError";
		this.selector = selector;
	}
}
