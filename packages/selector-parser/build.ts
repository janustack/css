import { dts } from "bun-plugin-dtsx";

await Bun.$`rm -rf dist`;

await Bun.$`zig build`;

const result = await Bun.build({
	entrypoints: ["src/ts/main.ts"],
	metafile: "meta.json",
	plugins: [dts()],
	target: "browser",
	footer: "// Built with love by ACY in Florida",
	minify: true,
	outdir: "dist",
	root: "src/ts",
});

await Bun.$`cp src/wasm/lib.wasm dist/`;

if (result.metafile) {
	for (const [path, meta] of Object.entries(result.metafile.outputs)) {
		const megabytes = meta.bytes / 1_000_000;
		Bun.stdout.write(`${path}: ${megabytes} mb`);
	}
}
