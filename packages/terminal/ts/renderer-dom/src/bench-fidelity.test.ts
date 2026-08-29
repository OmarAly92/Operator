import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore } from "@operator/terminal-core";
import { DomBlockRenderer } from "./dom-block-renderer";

// The bench harness verifies renderer identity and version but never that the
// bytes it wrote were actually rendered. A renderer that silently dropped the
// workload would post an unbeatable throughput number, so the fidelity of the
// measured path is pinned here instead.

beforeAll(async () => {
	// jsdom rejects file: URLs, so this resolves the path rather than a URL.
	const wasmPath = join(
		dirname(fileURLToPath(import.meta.url)),
		"..", "..", "core", "wasm", "vt_core_bg.wasm",
	);
	const bytes = await readFile(wasmPath);
	await initTerminalCore(
		bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer,
	);
});

describe("large-output fidelity", () => {
	it("wraps every byte of the workload and retains exactly the scrollback", () => {
		const columns = 120;
		const scrollback = 5000;
		const core = createTerminalCore({ columns, scrollback });

		// The bench workload shape: bytes of "x" with no newlines, written in
		// 64 KiB chunks. Scaled down here so the assertion stays fast; the
		// wrapping and trimming behaviour under test does not depend on size.
		const total = 1_200_000;
		const chunk = new Uint8Array(65_536).fill(0x78);
		let written = 0;
		while (written < total) {
			const size = Math.min(chunk.length, total - written);
			core.feed(size === chunk.length ? chunk : chunk.subarray(0, size));
			written += size;
		}

		const snapshot = core.snapshot();
		const rowCount = snapshot.rows.length / 2;
		expect(rowCount).toBe(scrollback);

		// Every retained row must be a full wrapped line of the workload byte,
		// which is what proves the parse ran rather than the bytes vanishing.
		const text = new TextDecoder().decode(snapshot.content);
		expect(text.length).toBe(rowCount * columns - columns + (total % columns || columns));
		expect(/^x+$/.test(text)).toBe(true);
	});

	it("paints the visible window and reports the paint", async () => {
		const container = document.createElement("div");
		Object.defineProperty(container, "clientHeight", { value: 400, configurable: true });
		document.body.append(container);

		const core = createTerminalCore({ columns: 120, scrollback: 5000 });
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);

		const painted = new Promise<void>((resolve) => {
			const off = renderer.onPaint(() => {
				off();
				resolve();
			});
		});

		core.feed(new Uint8Array(200_000).fill(0x78));
		await painted;

		const rows = container.querySelectorAll("[data-terminal-row]");
		expect(rows.length).toBeGreaterThan(0);
		// Virtualized: a fraction of the ~1,667 wrapped rows, not all of them.
		expect(rows.length).toBeLessThan(200);
		expect(rows[0].textContent).toMatch(/^x+$/);

		renderer.dispose();
		container.remove();
	});
});
