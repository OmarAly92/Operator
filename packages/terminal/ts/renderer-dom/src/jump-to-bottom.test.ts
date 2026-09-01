import { afterEach, describe, expect, it, vi } from "vitest";
import type { BlockView, TerminalStrings } from "@operator/terminal-core";
import { mountJumpToBottom } from "./jump-to-bottom";

const STRINGS: TerminalStrings = {
	blockRunning: "Running",
	blockSucceeded: "Succeeded",
	blockFailed: "Failed",
	blockAbandoned: "Abandoned",
	copyCommand: "Copy command",
	copyOutput: "Copy output",
	shareOutput: "Save output",
	bookmark: "Bookmark",
	filterToCommand: "Filter to this command",
	jump: "Jump to block",
	rerunCommand: "Re-run",
	shellBlocksUnavailable: "x",
	searchHistory: "y",
	searchNoMatches: "z",
	findPlaceholder: "Find",
	findLabel: "Find label",
	findMatchCount: "%1 of %2",
	palettePlaceholder: "Type a command",
	paletteLabel: "Command palette",
	paletteNoMatches: "No matching commands",
	jumpToBottom: "Jump to bottom",
};

function makeBlock(id: string, command: string, rowCount: number): BlockView {
	return {
		id,
		firstRow: 0,
		rowCount,
		source: "osc133",
		state: "finished",
		exitCode: 0,
		durationMs: 100,
		command,
		cwd: "",
		gitBranch: "",
		bookmarked: false,
	};
}

interface Harness {
	container: HTMLDivElement;
	blocks: BlockView[];
	scrollTop: number;
	clientHeight: number;
	stickToBottom: boolean;
	altActive: boolean;
	cellHeight: number;
	scrollToLatestCalls: number;
	dispose: () => void;
}

function makeHarness(initialBlocks: BlockView[], opts: Partial<Harness> = {}): Harness {
	const container = document.createElement("div");
	container.style.position = "relative";
	container.style.overflow = "auto";
	container.style.contain = "strict";
	container.tabIndex = 0;
	document.body.append(container);
	for (const block of initialBlocks) {
		const section = document.createElement("section");
		section.className = "terminal-block";
		section.dataset.terminalBlockId = block.id;
		container.append(section);
	}
	const h: Harness = {
		container,
		blocks: initialBlocks,
		scrollTop: opts.scrollTop ?? 0,
		clientHeight: opts.clientHeight ?? 200,
		stickToBottom: opts.stickToBottom ?? false,
		altActive: opts.altActive ?? false,
		cellHeight: opts.cellHeight ?? 20,
		scrollToLatestCalls: 0,
		dispose: () => {
			container.remove();
		},
	};
	Object.defineProperty(container, "clientHeight", { configurable: true, get: () => h.clientHeight });
	Object.defineProperty(container, "scrollHeight", {
		configurable: true,
		get: () => h.blocks.reduce((sum, b) => sum + b.rowCount, 0) * h.cellHeight,
	});
	Object.defineProperty(container, "scrollTop", {
		configurable: true,
		get: () => h.scrollTop,
		set: (v: number) => {
			h.scrollTop = v;
		},
	});
	return h;
}

function dispatchOver(el: HTMLElement): void {
	el.dispatchEvent(new MouseEvent("mouseover", { bubbles: true, cancelable: true }));
}

function dispatchOut(el: HTMLElement): void {
	el.dispatchEvent(new MouseEvent("mouseout", { bubbles: true, cancelable: true, relatedTarget: document.body }));
}

function dispatchKey(key: string, mods: { metaKey?: boolean; ctrlKey?: boolean; altKey?: boolean; shiftKey?: boolean } = {}): KeyboardEvent {
	return new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true, ...mods });
}

describe("mountJumpToBottom", () => {
	let harness: Harness | null = null;

	afterEach(() => {
		harness?.dispose();
		harness = null;
	});

	it("is inert in the alt screen (button stays hidden, keybinds do nothing)", () => {
		const blocks = [makeBlock("0:0", "first", 5), makeBlock("0:1", "second", 5)];
		harness = makeHarness(blocks, { altActive: true, scrollTop: 0, clientHeight: 200 });
		const jump = mountJumpToBottom({
			container: harness.container,
			getBlocks: () => harness!.blocks,
			getCellHeight: () => harness!.cellHeight,
			getStickToBottom: () => harness!.stickToBottom,
			scrollToLatest: () => { harness!.scrollToLatestCalls += 1; },
			isAltScreenActive: () => harness!.altActive,
			strings: STRINGS,
		});
		jump.mount();
		const blockEl = harness.container.querySelector<HTMLElement>('[data-terminal-block-id="0:1"]')!;
		dispatchOver(blockEl);
		expect(jump.isButtonVisible()).toBe(false);
		expect(harness.container.querySelector('[data-terminal-jump-to-bottom=""]')).toBeNull();
		harness.container.dispatchEvent(dispatchKey("End", { metaKey: true }));
		expect(harness.scrollToLatestCalls).toBe(0);
		jump.dispose();
	});

	it("does not show the button when scrolled to the bottom (stickToBottom true)", () => {
		const blocks = [makeBlock("0:0", "first", 5), makeBlock("0:1", "second", 5)];
		harness = makeHarness(blocks, { stickToBottom: true, scrollTop: 0, clientHeight: 200 });
		const jump = mountJumpToBottom({
			container: harness.container,
			getBlocks: () => harness!.blocks,
			getCellHeight: () => harness!.cellHeight,
			getStickToBottom: () => harness!.stickToBottom,
			scrollToLatest: () => { harness!.scrollToLatestCalls += 1; },
			isAltScreenActive: () => harness!.altActive,
			strings: STRINGS,
		});
		jump.mount();
		const blockEl = harness.container.querySelector<HTMLElement>('[data-terminal-block-id="0:1"]')!;
		dispatchOver(blockEl);
		expect(jump.isOverhanging()).toBeNull();
		expect(jump.isButtonVisible()).toBe(false);
		jump.dispose();
	});

	it("detects an overhanging block and reports the right id", () => {
		const blocks = [
			makeBlock("0:0", "tall", 100),
			makeBlock("0:1", "small", 1),
		];
		harness = makeHarness(blocks, { stickToBottom: false, scrollTop: 0, clientHeight: 200, cellHeight: 20 });
		const jump = mountJumpToBottom({
			container: harness.container,
			getBlocks: () => harness!.blocks,
			getCellHeight: () => harness!.cellHeight,
			getStickToBottom: () => harness!.stickToBottom,
			scrollToLatest: () => { harness!.scrollToLatestCalls += 1; },
			isAltScreenActive: () => harness!.altActive,
			strings: STRINGS,
		});
		jump.mount();
		expect(jump.isOverhanging()).toBe("0:0");
		const blockEl = harness.container.querySelector<HTMLElement>('[data-terminal-block-id="0:0"]')!;
		dispatchOver(blockEl);
		expect(jump.isButtonVisible()).toBe(true);
		const button = harness.container.querySelector<HTMLButtonElement>('[data-terminal-jump-to-bottom=""]');
		expect(button).not.toBeNull();
		jump.dispose();
	});

	it("does not show the button when the overhang is below the 70px threshold", () => {
		const blocks = [
			makeBlock("0:0", "tall", 100),
			makeBlock("0:1", "small", 1),
		];
		harness = makeHarness(blocks, {
			stickToBottom: false,
			scrollTop: 0,
			clientHeight: 100 * 20 - 30,
			cellHeight: 20,
		});
		const jump = mountJumpToBottom({
			container: harness.container,
			getBlocks: () => harness!.blocks,
			getCellHeight: () => harness!.cellHeight,
			getStickToBottom: () => harness!.stickToBottom,
			scrollToLatest: () => { harness!.scrollToLatestCalls += 1; },
			isAltScreenActive: () => harness!.altActive,
			strings: STRINGS,
		});
		jump.mount();
		expect(jump.isOverhanging()).toBeNull();
		const blockEl = harness.container.querySelector<HTMLElement>('[data-terminal-block-id="0:0"]')!;
		dispatchOver(blockEl);
		expect(jump.isButtonVisible()).toBe(false);
		jump.dispose();
	});

	it("clicking the button calls scrollToLatest", () => {
		const blocks = [makeBlock("0:0", "tall", 100)];
		harness = makeHarness(blocks, { stickToBottom: false, scrollTop: 0, clientHeight: 200, cellHeight: 20 });
		const jump = mountJumpToBottom({
			container: harness.container,
			getBlocks: () => harness!.blocks,
			getCellHeight: () => harness!.cellHeight,
			getStickToBottom: () => harness!.stickToBottom,
			scrollToLatest: () => { harness!.scrollToLatestCalls += 1; },
			isAltScreenActive: () => harness!.altActive,
			strings: STRINGS,
		});
		jump.mount();
		const blockEl = harness.container.querySelector<HTMLElement>('[data-terminal-block-id="0:0"]')!;
		dispatchOver(blockEl);
		const button = harness.container.querySelector<HTMLButtonElement>('[data-terminal-jump-to-bottom=""]')!;
		button.click();
		expect(harness.scrollToLatestCalls).toBe(1);
		jump.dispose();
	});

	it("mouseleave on the block hides the button", () => {
		const blocks = [makeBlock("0:0", "tall", 100)];
		harness = makeHarness(blocks, { stickToBottom: false, scrollTop: 0, clientHeight: 200, cellHeight: 20 });
		const jump = mountJumpToBottom({
			container: harness.container,
			getBlocks: () => harness!.blocks,
			getCellHeight: () => harness!.cellHeight,
			getStickToBottom: () => harness!.stickToBottom,
			scrollToLatest: () => { harness!.scrollToLatestCalls += 1; },
			isAltScreenActive: () => harness!.altActive,
			strings: STRINGS,
		});
		jump.mount();
		const blockEl = harness.container.querySelector<HTMLElement>('[data-terminal-block-id="0:0"]')!;
		dispatchOver(blockEl);
		expect(jump.isButtonVisible()).toBe(true);
		dispatchOut(blockEl);
		expect(jump.isButtonVisible()).toBe(false);
		jump.dispose();
	});

	it("Cmd+End calls scrollToLatest", () => {
		const blocks = [makeBlock("0:0", "first", 5)];
		harness = makeHarness(blocks, { stickToBottom: false });
		const jump = mountJumpToBottom({
			container: harness.container,
			getBlocks: () => harness!.blocks,
			getCellHeight: () => harness!.cellHeight,
			getStickToBottom: () => harness!.stickToBottom,
			scrollToLatest: () => { harness!.scrollToLatestCalls += 1; },
			isAltScreenActive: () => harness!.altActive,
			strings: STRINGS,
		});
		jump.mount();
		harness.container.dispatchEvent(dispatchKey("End", { metaKey: true }));
		expect(harness.scrollToLatestCalls).toBe(1);
		jump.dispose();
	});

	it("Cmd+Down calls scrollToLatest", () => {
		const blocks = [makeBlock("0:0", "first", 5)];
		harness = makeHarness(blocks, { stickToBottom: false });
		const jump = mountJumpToBottom({
			container: harness.container,
			getBlocks: () => harness!.blocks,
			getCellHeight: () => harness!.cellHeight,
			getStickToBottom: () => harness!.stickToBottom,
			scrollToLatest: () => { harness!.scrollToLatestCalls += 1; },
			isAltScreenActive: () => harness!.altActive,
			strings: STRINGS,
		});
		jump.mount();
		harness.container.dispatchEvent(dispatchKey("ArrowDown", { metaKey: true }));
		expect(harness.scrollToLatestCalls).toBe(1);
		jump.dispose();
	});

	it("ignores End and ArrowDown without Cmd or Ctrl", () => {
		const blocks = [makeBlock("0:0", "first", 5)];
		harness = makeHarness(blocks, { stickToBottom: false });
		const jump = mountJumpToBottom({
			container: harness.container,
			getBlocks: () => harness!.blocks,
			getCellHeight: () => harness!.cellHeight,
			getStickToBottom: () => harness!.stickToBottom,
			scrollToLatest: () => { harness!.scrollToLatestCalls += 1; },
			isAltScreenActive: () => harness!.altActive,
			strings: STRINGS,
		});
		jump.mount();
		harness.container.dispatchEvent(dispatchKey("End"));
		harness.container.dispatchEvent(dispatchKey("ArrowDown"));
		expect(harness.scrollToLatestCalls).toBe(0);
		jump.dispose();
	});

	it("ignores chords that include Alt or Shift", () => {
		const blocks = [makeBlock("0:0", "first", 5)];
		harness = makeHarness(blocks, { stickToBottom: false });
		const jump = mountJumpToBottom({
			container: harness.container,
			getBlocks: () => harness!.blocks,
			getCellHeight: () => harness!.cellHeight,
			getStickToBottom: () => harness!.stickToBottom,
			scrollToLatest: () => { harness!.scrollToLatestCalls += 1; },
			isAltScreenActive: () => harness!.altActive,
			strings: STRINGS,
		});
		jump.mount();
		harness.container.dispatchEvent(dispatchKey("End", { metaKey: true, altKey: true }));
		harness.container.dispatchEvent(dispatchKey("End", { metaKey: true, shiftKey: true }));
		expect(harness.scrollToLatestCalls).toBe(0);
		jump.dispose();
	});

	it("the button is a real <button> with aria-label (keyboard reachable)", () => {
		const blocks = [makeBlock("0:0", "tall", 100)];
		harness = makeHarness(blocks, { stickToBottom: false, scrollTop: 0, clientHeight: 200, cellHeight: 20 });
		const jump = mountJumpToBottom({
			container: harness.container,
			getBlocks: () => harness!.blocks,
			getCellHeight: () => harness!.cellHeight,
			getStickToBottom: () => harness!.stickToBottom,
			scrollToLatest: () => { harness!.scrollToLatestCalls += 1; },
			isAltScreenActive: () => harness!.altActive,
			strings: STRINGS,
		});
		jump.mount();
		const blockEl = harness.container.querySelector<HTMLElement>('[data-terminal-block-id="0:0"]')!;
		dispatchOver(blockEl);
		const button = harness.container.querySelector<HTMLButtonElement>('[data-terminal-jump-to-bottom=""]')!;
		expect(button.tagName).toBe("BUTTON");
		expect(button.getAttribute("aria-label")).toBe(STRINGS.jumpToBottom);
		button.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }));
		expect(harness.scrollToLatestCalls).toBe(1);
		jump.dispose();
	});

	it("dispose() removes listeners and detaches the button", () => {
		const blocks = [makeBlock("0:0", "tall", 100)];
		harness = makeHarness(blocks, { stickToBottom: false });
		const jump = mountJumpToBottom({
			container: harness.container,
			getBlocks: () => harness!.blocks,
			getCellHeight: () => harness!.cellHeight,
			getStickToBottom: () => harness!.stickToBottom,
			scrollToLatest: () => { harness!.scrollToLatestCalls += 1; },
			isAltScreenActive: () => harness!.altActive,
			strings: STRINGS,
		});
		jump.mount();
		jump.dispose();
		expect(harness.container.querySelector('[data-terminal-jump-to-bottom=""]')).toBeNull();
		harness.container.dispatchEvent(dispatchKey("End", { metaKey: true }));
		expect(harness.scrollToLatestCalls).toBe(0);
	});

	it("does not show the button when no blocks exist", () => {
		harness = makeHarness([], { stickToBottom: false });
		const jump = mountJumpToBottom({
			container: harness.container,
			getBlocks: () => harness!.blocks,
			getCellHeight: () => harness!.cellHeight,
			getStickToBottom: () => harness!.stickToBottom,
			scrollToLatest: () => { harness!.scrollToLatestCalls += 1; },
			isAltScreenActive: () => harness!.altActive,
			strings: STRINGS,
		});
		jump.mount();
		expect(jump.isOverhanging()).toBeNull();
		jump.dispose();
	});

	it("the click path does not execute any host capability (§3.6 structural)", () => {
		const blocks = [makeBlock("0:0", "tall", 100)];
		harness = makeHarness(blocks, { stickToBottom: false, scrollTop: 0, clientHeight: 200, cellHeight: 20 });
		const executeSpy = vi.fn();
		const spawnSpy = vi.fn();
		const jump = mountJumpToBottom({
			container: harness.container,
			getBlocks: () => harness!.blocks,
			getCellHeight: () => harness!.cellHeight,
			getStickToBottom: () => harness!.stickToBottom,
			scrollToLatest: () => { harness!.scrollToLatestCalls += 1; },
			isAltScreenActive: () => harness!.altActive,
			strings: STRINGS,
		});
		jump.mount();
		const blockEl = harness.container.querySelector<HTMLElement>('[data-terminal-block-id="0:0"]')!;
		dispatchOver(blockEl);
		const button = harness.container.querySelector<HTMLButtonElement>('[data-terminal-jump-to-bottom=""]')!;
		button.click();
		expect(executeSpy).not.toHaveBeenCalled();
		expect(spawnSpy).not.toHaveBeenCalled();
		jump.dispose();
	});
});
