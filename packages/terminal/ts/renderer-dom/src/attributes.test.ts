import { describe, expect, it } from "vitest";
import {
	ATTR_BLINK,
	ATTR_CURLY_UNDERLINE,
	ATTR_DOUBLE_UNDERLINE,
	ATTR_HIDDEN,
	ATTR_ITALIC,
	ATTR_OVERLINE,
	ATTR_STRIKE,
	ATTR_UNDERLINE,
	STYLE_DEFAULT_UNDERLINE,
} from "@operator/terminal-core";
import { applyAttributes, CLASS_BLINK, decorationAttributes, underlinedText } from "./attributes";
import { buildRowNode, type RowSource } from "./row-builder";
import { DEFAULT_FEATURES } from "./features";

const RGB_MAGENTA = 0x0200_0000 | (255 << 16) | 255;

function rowOf(text: string, attrs: number, underline = STYLE_DEFAULT_UNDERLINE, features = DEFAULT_FEATURES): HTMLElement {
	const content = new TextEncoder().encode(text);
	const source: RowSource = {
		content,
		rows: Uint32Array.from([0, content.byteLength]),
		runRanges: Uint32Array.from([0, 1]),
		stylePairs: Uint32Array.from([content.byteLength, 255, 254, attrs, underline, 0]),
	};
	return buildRowNode(source, 0, 0, new TextDecoder("utf-8", { fatal: true }), 8, features);
}

describe("decorationAttributes", () => {
	it("maps each bit to its decoration", () => {
		expect(decorationAttributes(ATTR_ITALIC, STYLE_DEFAULT_UNDERLINE)).toMatchObject({ italic: true, underline: null, decor: null });
		expect(decorationAttributes(ATTR_UNDERLINE, STYLE_DEFAULT_UNDERLINE)).toMatchObject({ underline: "single", decor: "u" });
		expect(decorationAttributes(ATTR_DOUBLE_UNDERLINE, STYLE_DEFAULT_UNDERLINE).underline).toBe("double");
		expect(decorationAttributes(ATTR_CURLY_UNDERLINE | ATTR_STRIKE | ATTR_OVERLINE, STYLE_DEFAULT_UNDERLINE)).toMatchObject({ underline: "curly", decor: "uso" });
		expect(decorationAttributes(ATTR_STRIKE, STYLE_DEFAULT_UNDERLINE).decor).toBe("s");
		expect(decorationAttributes(ATTR_HIDDEN | ATTR_BLINK, STYLE_DEFAULT_UNDERLINE)).toMatchObject({ hidden: true, blink: true });
	});

	it("resolves an explicit underline colour and leaves the default to currentColor", () => {
		expect(decorationAttributes(ATTR_UNDERLINE, RGB_MAGENTA).underlineColour).toBe("rgb(255 0 255)");
		expect(decorationAttributes(ATTR_UNDERLINE, STYLE_DEFAULT_UNDERLINE).underlineColour).toBeNull();
	});

	it("keeps an underline visible across spaces with no-break spaces", () => {
		expect(underlinedText("a b")).toBe("a b");
	});
});

describe("row attributes under attributes: warp", () => {
	const warp = { ...DEFAULT_FEATURES, attributes: "warp" as const };

	it("marks the run with data attributes and the underline colour", () => {
		const run = rowOf("x y", ATTR_ITALIC | ATTR_CURLY_UNDERLINE | ATTR_STRIKE, RGB_MAGENTA, warp).querySelector<HTMLElement>(".terminal-run")!;
		expect(run.dataset.italic).toBe("");
		expect(run.dataset.underline).toBe("curly");
		expect(run.dataset.decor).toBe("us");
		expect(run.style.getPropertyValue("--terminal-underline")).toBe("rgb(255 0 255)");
		expect(run.textContent).toBe("x y");
	});

	it("hides a hidden run and tags a blinking one", () => {
		const run = rowOf("secret", ATTR_HIDDEN | ATTR_BLINK, STYLE_DEFAULT_UNDERLINE, warp).querySelector<HTMLElement>(".terminal-run")!;
		expect(run.dataset.hidden).toBe("");
		expect(run.classList.contains(CLASS_BLINK)).toBe(true);
		expect(run.textContent).toBe("secret");
	});

	it("does nothing under the plain default", () => {
		const run = rowOf("x y", ATTR_ITALIC | ATTR_UNDERLINE | ATTR_STRIKE | ATTR_HIDDEN | ATTR_BLINK, RGB_MAGENTA).querySelector<HTMLElement>(".terminal-run")!;
		expect(Object.keys(run.dataset)).toEqual(["terminalRun"]);
		expect(run.className).toBe("terminal-run");
		expect(run.style.getPropertyValue("--terminal-underline")).toBe("");
		expect(run.textContent).toBe("x y");
	});

	it("applyAttributes reports whether the run is underlined", () => {
		const run = document.createElement("span");
		expect(applyAttributes(run, ATTR_STRIKE, STYLE_DEFAULT_UNDERLINE)).toBe(false);
		expect(applyAttributes(run, ATTR_UNDERLINE, STYLE_DEFAULT_UNDERLINE)).toBe(true);
	});
});

describe("row-builder merge predicate under attributes: warp", () => {
	const warp = { ...DEFAULT_FEATURES, attributes: "warp" as const };

	it("does not merge adjacent runs that share paint but differ in attrs, under warp", () => {
		const content = new TextEncoder().encode("ab");
		const source: RowSource = {
			content,
			rows: Uint32Array.from([0, content.byteLength]),
			runRanges: Uint32Array.from([0, 2]),
			stylePairs: Uint32Array.from([
				1, 255, 254, ATTR_ITALIC, STYLE_DEFAULT_UNDERLINE, 0,
				2, 255, 254, 0, STYLE_DEFAULT_UNDERLINE, 0,
			]),
		};
		const row = buildRowNode(source, 0, 0, new TextDecoder("utf-8", { fatal: true }), 8, warp);
		const runs = row.querySelectorAll<HTMLElement>(".terminal-run");
		expect(runs.length).toBe(2);
		expect(runs[0]!.dataset.italic).toBe("");
		expect(runs[1]!.dataset.italic).toBeUndefined();
	});

	it("still merges adjacent runs sharing paint but differing in attrs, under plain", () => {
		const content = new TextEncoder().encode("ab");
		const source: RowSource = {
			content,
			rows: Uint32Array.from([0, content.byteLength]),
			runRanges: Uint32Array.from([0, 2]),
			stylePairs: Uint32Array.from([
				1, 255, 254, ATTR_ITALIC, STYLE_DEFAULT_UNDERLINE, 0,
				2, 255, 254, 0, STYLE_DEFAULT_UNDERLINE, 0,
			]),
		};
		const row = buildRowNode(source, 0, 0, new TextDecoder("utf-8", { fatal: true }), 8, DEFAULT_FEATURES);
		const runs = row.querySelectorAll<HTMLElement>(".terminal-run");
		expect(runs.length).toBe(1);
	});
});
