import type { WasmExports } from "./types.js";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

export async function loadWasm(
    source?: Response | Uint8Array | WebAssembly.Module,
): Promise<WasmExports> {
    let instance: WebAssembly.Instance;
    const imports = { env: {} };
    if (source) {
        if (source instanceof WebAssembly.Module) {
            instance = await WebAssembly.instantiate(source, imports);
        } else if (source instanceof Response) {
            const result = await WebAssembly.instantiateStreaming(source, imports);
            instance = result.instance;
        } else {
            const result = await WebAssembly.instantiate(source, imports);
            instance = result.instance;
        }
    } else {
        try {
            const url = new URL("./lib.wasm", import.meta.url);
            const result = await WebAssembly.instantiateStreaming(
                fetch(url),
                imports,
            );
            instance = result.instance;
        } catch {
            const path = "./lib.wasm";
            const url = new URL(path, import.meta.url);
            const bytes = await Bun.file(url).bytes();
            const result = await WebAssembly.instantiate(bytes, imports);
            instance = result.instance;
        }
    }
    const exports = instance.exports as unknown as WasmExports;
    return exports;
}

export class Buffer {
    private byteOffset = 0;
    private dataView: DataView;

    constructor(buffer: Uint8Array) {
        this.
    }

    private readString(): string {
        return this.textDecoder.decode(bytes);
    }

    private readU8(): number {
        return this.dataView.getUint8(this.byteOffset, true);
    }

    private readU32(): number {
        return this.dataView.getUint32(this.byteOffset, true);
    }

}
