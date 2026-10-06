import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore } from "@operator/terminal-core";
import { DomBlockRenderer } from "./index";
import { feed, flushRepaint, font, loadedCore } from "./renderer-harness";

beforeAll(async () => {
	await loadedCore();
});

function scrollable(): HTMLElement {
	const container = document.createElement("div");
	Object.defineProperty(container, "clientHeight", { value: 100, configurable: true });
	Object.defineProperty(container, "scrollHeight", { value: 100_000, configurable: true });
	Object.defineProperty(container, "scrollTop", { value: 0, configurable: true, writable: true });
	return container;
}

describe("older rows prepended at the top of scrollback", () => {
	it("keep the row under the top edge where it was", async () => {
		const container = scrollable();
		const core = createTerminalCore({ columns: 20, limits: { rows: 60, bytes: 0xffff_ffff }, rows: 2 });
		for (let i = 0; i < 100; i += 1) feed(core, `line ${i}\r\n`);
		const front = core.snapshot().firstStableRow;
		expect(front).toBeGreaterThan(3);
		const renderer = new DomBlockRenderer();
		renderer.mount(container, core);
		renderer.setFont(font);
		const rowHeight = renderer.measure().cellHeight;
		container.scrollTop = Math.round(rowHeight * 2);
		container.dispatchEvent(new Event("scroll"));
		await flushRepaint();
		const anchor = renderer.scrollAnchor()!;
		const textBefore = container.querySelector(`[data-terminal-row="${anchor.stableRow}"]`)?.textContent;
		const before = container.scrollTop;

		feed(
			core,
			`\x1b]7000;v=1;history=${front - 3},3;cols=5\x1b\\old a\r\nold b\r\nold c\r\n\x1b]7000;v=1;older=0\x1b\\`,
		);
		await flushRepaint();

		expect(core.snapshot().firstStableRow).toBe(front - 3);
		expect(renderer.scrollAnchor()).toEqual(anchor);
		expect(container.scrollTop).toBeCloseTo(before + 3 * rowHeight, 3);
		expect(container.querySelector(`[data-terminal-row="${anchor.stableRow}"]`)?.textContent).toBe(textBefore);
		renderer.dispose();
	});
});
