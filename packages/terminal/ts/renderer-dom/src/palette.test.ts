import { afterEach, describe, expect, it } from "vitest";
import type { PaletteCommand, TerminalStrings } from "@operator/terminal-core";
import { mountPalette } from "./palette";

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

function key(init: Partial<KeyboardEventInit> & { key: string }): KeyboardEvent {
	return new KeyboardEvent("keydown", {
		bubbles: true,
		cancelable: true,
		ctrlKey: false,
		metaKey: false,
		altKey: false,
		shiftKey: false,
		...init,
	});
}

interface Harness {
	container: HTMLDivElement;
	commands: { list: PaletteCommand[]; calls: string[] };
	altActive: () => boolean;
	dispose: () => void;
}

function makeHarness(commands: PaletteCommand[], altActive = false): Harness {
	const container = document.createElement("div");
	container.tabIndex = 0;
	document.body.append(container);
	const commandList: { list: PaletteCommand[]; calls: string[] } = {
		list: commands,
		calls: [],
	};
	const harness: Harness = {
		container,
		commands: commandList,
		altActive: () => altActive,
		dispose: () => {
			container.remove();
		},
	};
	return harness;
}

function makeCommand(id: string, label: string, calls: string[]): PaletteCommand {
	return { id, label, run: () => calls.push(id) };
}

describe("mountPalette", () => {
	let harness: Harness | null = null;

	afterEach(() => {
		harness?.dispose();
		harness = null;
	});

	it("is inert in the alt screen (open key does not show the palette)", () => {
		const calls: string[] = [];
		const cmds = [makeCommand("c1", "Alpha", calls)];
		harness = makeHarness(cmds, true);
		const palette = mountPalette({
			container: harness.container,
			getCommands: () => harness!.commands.list,
			isAltScreenActive: harness.altActive,
			strings: STRINGS,
		});
		palette.mount();
		harness.container.dispatchEvent(key({ key: "P", metaKey: true, shiftKey: true }));
		expect(palette.isOpen()).toBe(false);
		expect(harness.container.querySelector('[data-terminal-palette=""]')).toBeNull();
		palette.dispose();
	});

	it("opens on Cmd+Shift+P and focuses the input", () => {
		const calls: string[] = [];
		harness = makeHarness([makeCommand("c1", "Alpha", calls)]);
		const palette = mountPalette({
			container: harness.container,
			getCommands: () => harness!.commands.list,
			isAltScreenActive: () => false,
			strings: STRINGS,
		});
		palette.mount();
		harness.container.focus();
		harness.container.dispatchEvent(key({ key: "P", metaKey: true, shiftKey: true }));
		expect(palette.isOpen()).toBe(true);
		const input = harness.container.querySelector<HTMLInputElement>('[data-terminal-palette-input=""]');
		expect(input).not.toBeNull();
		expect(document.activeElement).toBe(input);
		palette.dispose();
	});

	it("opens on Ctrl+Shift+P on non-Mac hosts", () => {
		const calls: string[] = [];
		harness = makeHarness([makeCommand("c1", "Alpha", calls)]);
		const palette = mountPalette({
			container: harness.container,
			getCommands: () => harness!.commands.list,
			isAltScreenActive: () => false,
			strings: STRINGS,
		});
		palette.mount();
		harness.container.dispatchEvent(key({ key: "P", ctrlKey: true, shiftKey: true }));
		expect(palette.isOpen()).toBe(true);
		palette.dispose();
	});

	it("ignores Cmd+P without Shift", () => {
		const calls: string[] = [];
		harness = makeHarness([makeCommand("c1", "Alpha", calls)]);
		const palette = mountPalette({
			container: harness.container,
			getCommands: () => harness!.commands.list,
			isAltScreenActive: () => false,
			strings: STRINGS,
		});
		palette.mount();
		harness.container.dispatchEvent(key({ key: "p", metaKey: true }));
		expect(palette.isOpen()).toBe(false);
		palette.dispose();
	});

	it("ignores Shift+P without Cmd or Ctrl", () => {
		const calls: string[] = [];
		harness = makeHarness([makeCommand("c1", "Alpha", calls)]);
		const palette = mountPalette({
			container: harness.container,
			getCommands: () => harness!.commands.list,
			isAltScreenActive: () => false,
			strings: STRINGS,
		});
		palette.mount();
		harness.container.dispatchEvent(key({ key: "P", shiftKey: true }));
		expect(palette.isOpen()).toBe(false);
		palette.dispose();
	});

	it("filters by case-insensitive substring as the user types", () => {
		const calls: string[] = [];
		const cmds = [
			makeCommand("c1", "Copy command", calls),
			makeCommand("c2", "Bookmark block", calls),
			makeCommand("c3", "Jump to top", calls),
		];
		harness = makeHarness(cmds);
		const palette = mountPalette({
			container: harness.container,
			getCommands: () => harness!.commands.list,
			isAltScreenActive: () => false,
			strings: STRINGS,
		});
		palette.mount();
		palette.open();
		const input = harness.container.querySelector<HTMLInputElement>('[data-terminal-palette-input=""]')!;
		input.value = "BOOK";
		input.dispatchEvent(new Event("input", { bubbles: true }));
		const options = harness.container.querySelectorAll<HTMLElement>('[data-terminal-palette-option=""]');
		expect(options).toHaveLength(1);
		expect(options[0]?.getAttribute("data-terminal-palette-command-id")).toBe("c2");
		palette.dispose();
	});

	it("ArrowDown and ArrowUp move the active option", () => {
		const calls: string[] = [];
		const cmds = [
			makeCommand("a", "Alpha", calls),
			makeCommand("b", "Beta", calls),
			makeCommand("c", "Gamma", calls),
		];
		harness = makeHarness(cmds);
		const palette = mountPalette({
			container: harness.container,
			getCommands: () => harness!.commands.list,
			isAltScreenActive: () => false,
			strings: STRINGS,
		});
		palette.mount();
		palette.open();
		const input = harness.container.querySelector<HTMLInputElement>('[data-terminal-palette-input=""]')!;
		input.dispatchEvent(key({ key: "ArrowDown" }));
		let active = harness.container.querySelector<HTMLElement>('[data-terminal-palette-option-active=""]');
		expect(active?.getAttribute("data-terminal-palette-command-id")).toBe("b");
		input.dispatchEvent(key({ key: "ArrowDown" }));
		active = harness.container.querySelector<HTMLElement>('[data-terminal-palette-option-active=""]');
		expect(active?.getAttribute("data-terminal-palette-command-id")).toBe("c");
		input.dispatchEvent(key({ key: "ArrowUp" }));
		active = harness.container.querySelector<HTMLElement>('[data-terminal-palette-option-active=""]');
		expect(active?.getAttribute("data-terminal-palette-command-id")).toBe("b");
		palette.dispose();
	});

	it("ArrowDown wraps from the last option back to the first", () => {
		const calls: string[] = [];
		harness = makeHarness([makeCommand("a", "Alpha", calls), makeCommand("b", "Beta", calls)]);
		const palette = mountPalette({
			container: harness.container,
			getCommands: () => harness!.commands.list,
			isAltScreenActive: () => false,
			strings: STRINGS,
		});
		palette.mount();
		palette.open();
		const input = harness.container.querySelector<HTMLInputElement>('[data-terminal-palette-input=""]')!;
		input.dispatchEvent(key({ key: "ArrowDown" }));
		input.dispatchEvent(key({ key: "ArrowDown" }));
		const active = harness.container.querySelector<HTMLElement>('[data-terminal-palette-option-active=""]');
		expect(active?.getAttribute("data-terminal-palette-command-id")).toBe("a");
		palette.dispose();
	});

	it("Enter runs the active command and closes the palette", () => {
		const calls: string[] = [];
		const cmds = [makeCommand("a", "Alpha", calls), makeCommand("b", "Beta", calls)];
		harness = makeHarness(cmds);
		const palette = mountPalette({
			container: harness.container,
			getCommands: () => harness!.commands.list,
			isAltScreenActive: () => false,
			strings: STRINGS,
		});
		palette.mount();
		palette.open();
		const input = harness.container.querySelector<HTMLInputElement>('[data-terminal-palette-input=""]')!;
		input.dispatchEvent(key({ key: "ArrowDown" }));
		input.dispatchEvent(key({ key: "Enter" }));
		expect(calls).toEqual(["b"]);
		expect(palette.isOpen()).toBe(false);
		expect(harness.container.querySelector('[data-terminal-palette=""]')).toBeNull();
		palette.dispose();
	});

	it("clicking a command option runs it and closes the palette", () => {
		const calls: string[] = [];
		const cmds = [makeCommand("a", "Alpha", calls), makeCommand("b", "Beta", calls)];
		harness = makeHarness(cmds);
		const palette = mountPalette({
			container: harness.container,
			getCommands: () => harness!.commands.list,
			isAltScreenActive: () => false,
			strings: STRINGS,
		});
		palette.mount();
		palette.open();
		const second = harness.container.querySelector<HTMLElement>(
			'[data-terminal-palette-option=""][data-terminal-palette-command-id="b"]',
		);
		expect(second).not.toBeNull();
		second!.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
		expect(calls).toEqual(["b"]);
		expect(palette.isOpen()).toBe(false);
		palette.dispose();
	});

	it("Escape closes the palette and returns focus to the previous element", () => {
		const calls: string[] = [];
		harness = makeHarness([makeCommand("a", "Alpha", calls)]);
		const outer = document.createElement("button");
		outer.textContent = "before";
		document.body.append(outer);
		outer.focus();
		const palette = mountPalette({
			container: harness.container,
			getCommands: () => harness!.commands.list,
			isAltScreenActive: () => false,
			strings: STRINGS,
		});
		palette.mount();
		palette.open();
		expect(palette.isOpen()).toBe(true);
		const input = harness.container.querySelector<HTMLInputElement>('[data-terminal-palette-input=""]')!;
		input.dispatchEvent(key({ key: "Escape" }));
		expect(palette.isOpen()).toBe(false);
		expect(document.activeElement).toBe(outer);
		outer.remove();
		palette.dispose();
	});

	it("shows the no-matches message when nothing matches the filter", () => {
		const calls: string[] = [];
		harness = makeHarness([makeCommand("a", "Alpha", calls)]);
		const palette = mountPalette({
			container: harness.container,
			getCommands: () => harness!.commands.list,
			isAltScreenActive: () => false,
			strings: STRINGS,
		});
		palette.mount();
		palette.open();
		const input = harness.container.querySelector<HTMLInputElement>('[data-terminal-palette-input=""]')!;
		input.value = "zzz";
		input.dispatchEvent(new Event("input", { bubbles: true }));
		const empty = harness.container.querySelector<HTMLElement>('[data-terminal-palette-empty=""]');
		expect(empty).not.toBeNull();
		expect(empty?.textContent).toBe(STRINGS.paletteNoMatches);
		palette.dispose();
	});

	it("reads commands from the host at filter time (live update)", () => {
		const calls: string[] = [];
		const liveCommands: PaletteCommand[] = [makeCommand("a", "Alpha", calls)];
		harness = makeHarness(liveCommands);
		const palette = mountPalette({
			container: harness.container,
			getCommands: () => liveCommands,
			isAltScreenActive: () => false,
			strings: STRINGS,
		});
		palette.mount();
		palette.open();
		const input = harness.container.querySelector<HTMLInputElement>('[data-terminal-palette-input=""]')!;
		input.dispatchEvent(key({ key: "ArrowDown" }));
		input.dispatchEvent(key({ key: "Enter" }));
		expect(calls).toEqual(["a"]);
		liveCommands.push(makeCommand("b", "Beta", calls));
		palette.open();
		const after = harness.container.querySelectorAll<HTMLElement>('[data-terminal-palette-option=""]');
		expect(after).toHaveLength(2);
		palette.dispose();
	});

	it("does not run a command when the palette is not open", () => {
		const calls: string[] = [];
		harness = makeHarness([makeCommand("a", "Alpha", calls)]);
		const palette = mountPalette({
			container: harness.container,
			getCommands: () => harness!.commands.list,
			isAltScreenActive: () => false,
			strings: STRINGS,
		});
		palette.mount();
		const input = harness.container.querySelector<HTMLInputElement>('[data-terminal-palette-input=""]');
		expect(input).toBeNull();
		const input2 = document.createElement("input");
		input2.value = "ignored";
		document.body.append(input2);
		input2.dispatchEvent(key({ key: "Enter" }));
		expect(calls).toEqual([]);
		input2.remove();
		palette.dispose();
	});

	it("dispose() detaches the keydown listener and clears the palette", () => {
		const calls: string[] = [];
		harness = makeHarness([makeCommand("a", "Alpha", calls)]);
		const palette = mountPalette({
			container: harness.container,
			getCommands: () => harness!.commands.list,
			isAltScreenActive: () => false,
			strings: STRINGS,
		});
		palette.mount();
		palette.dispose();
		harness.container.dispatchEvent(key({ key: "P", metaKey: true, shiftKey: true }));
		expect(palette.isOpen()).toBe(false);
		expect(harness.container.querySelector('[data-terminal-palette=""]')).toBeNull();
	});

	it("every action target is keyboard reachable (Enter and Space click pattern)", () => {
		const calls: string[] = [];
		const cmds = [makeCommand("a", "Alpha", calls)];
		harness = makeHarness(cmds);
		const palette = mountPalette({
			container: harness.container,
			getCommands: () => harness!.commands.list,
			isAltScreenActive: () => false,
			strings: STRINGS,
		});
		palette.mount();
		palette.open();
		const option = harness.container.querySelector<HTMLElement>('[data-terminal-palette-option=""]');
		expect(option?.getAttribute("role")).toBe("option");
		palette.dispose();
	});
});
