import { act } from "@testing-library/react";
import { beforeAll, describe, expect, it, vi } from "vitest";
import type { HostCapabilities } from "@operator/terminal-core";
import { feed, flushRepaint, loadWasm, renderSurface } from "./surface-harness";

beforeAll(async () => {
	await loadWasm();
});

function hostWith(loadOlderOutput?: (before: number) => void): HostCapabilities {
	return {
		writeClipboard: async () => undefined,
		readClipboard: async () => "",
		openLink: async () => undefined,
		...(loadOlderOutput ? { loadOlderOutput } : {}),
	};
}

async function paint(): Promise<void> {
	await act(async () => {
		await flushRepaint();
		await flushRepaint();
	});
}

const button = (host: HTMLElement) => host.querySelector<HTMLButtonElement>("[data-terminal-load-older]");

function trimmedPast(core: ReturnType<typeof renderSurface>["core"]): number {
	for (let i = 0; i < 150; i += 1) feed(core, `line ${i}\r\n`);
	return core.snapshot().firstStableRow;
}

describe("TerminalSurface load older output", () => {
	it("offers the button once the host reports older rows and asks for the rows above the first one", async () => {
		const load = vi.fn<(before: number) => void>();
		const { core, host, unmount } = renderSurface({ host: hostWith(load) });
		const front = trimmedPast(core);
		await paint();
		expect(button(host)).toBeNull();

		feed(core, "\x1b]7000;v=1;older=0\x1b\\");
		await paint();
		expect(button(host)?.textContent).toBe("Load older output");

		act(() => button(host)!.click());
		expect(load).toHaveBeenCalledWith(front);
		expect(button(host)).toBeNull();

		feed(
			core,
			`\x1b]7000;v=1;history=${front - 2},2;cols=8\x1b\\older 1\r\nolder 2\r\n\x1b]7000;v=1;older=${front - 2}\x1b\\`,
		);
		await paint();
		expect(core.snapshot().firstStableRow).toBe(front - 2);
		expect(button(host)).toBeNull();
		unmount();
	});

	it("never offers the button to a host that cannot load", async () => {
		const { core, host, unmount } = renderSurface({ host: hostWith() });
		trimmedPast(core);
		feed(core, "\x1b]7000;v=1;older=0\x1b\\");
		await paint();
		expect(button(host)).toBeNull();
		unmount();
	});

	it("takes the button away when the surface unmounts", async () => {
		const load = vi.fn<(before: number) => void>();
		const { core, host, unmount } = renderSurface({ host: hostWith(load) });
		trimmedPast(core);
		feed(core, "\x1b]7000;v=1;older=0\x1b\\");
		await paint();
		const shown = button(host)!;
		unmount();
		expect(host.contains(shown)).toBe(false);
		shown.click();
		expect(load).not.toHaveBeenCalled();
	});
});
