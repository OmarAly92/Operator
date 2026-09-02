import { describe, expect, it } from "vitest";
import { encodeMouseReport } from "./mouse-report.js";

const noMods = { shift: false, alt: false, ctrl: false } as const;
const base = {
	column: 5,
	row: 3,
	sgrMouse: true,
	trackingLevel: 0b001,
	modifiers: noMods,
	altScreen: false,
} as const;

describe("encodeMouseReport", () => {
	it("returns null when the program has not asked for SGR encoding", () => {
		expect(encodeMouseReport({ ...base, sgrMouse: false, kind: "press", button: 0 })).toBeNull();
	});

	it("returns null when no tracking level is set", () => {
		expect(encodeMouseReport({ ...base, trackingLevel: 0, kind: "press", button: 0 })).toBeNull();
	});

	it("encodes a left press with Warp's button code and a trailing M", () => {
		expect(encodeMouseReport({ ...base, kind: "press", button: 0 })).toBe("\x1b[<0;5;3M");
	});

	it("encodes a right press as button 2", () => {
		expect(encodeMouseReport({ ...base, kind: "press", button: 2 })).toBe("\x1b[<2;5;3M");
	});

	it("encodes a release with a trailing m", () => {
		expect(encodeMouseReport({ ...base, kind: "release", button: 0 })).toBe("\x1b[<0;5;3m");
	});

	it("suppresses a drag when only click tracking is on", () => {
		expect(encodeMouseReport({ ...base, kind: "drag", button: 0 })).toBeNull();
	});

	it("encodes a left drag as the motion bit plus the button under 1002", () => {
		expect(encodeMouseReport({ ...base, trackingLevel: 0b010, kind: "drag", button: 0 })).toBe(
			"\x1b[<32;5;3M",
		);
	});

	it("encodes a right drag as 34", () => {
		expect(encodeMouseReport({ ...base, trackingLevel: 0b010, kind: "drag", button: 2 })).toBe(
			"\x1b[<34;5;3M",
		);
	});

	it("suppresses buttonless motion unless 1003 is on", () => {
		expect(encodeMouseReport({ ...base, trackingLevel: 0b010, kind: "move", button: 0 })).toBeNull();
		expect(encodeMouseReport({ ...base, trackingLevel: 0b100, kind: "move", button: 0 })).toBe(
			"\x1b[<35;5;3M",
		);
	});

	it("does not report buttonless motion in the alt screen unless 1003 is set", () => {
		expect(
			encodeMouseReport({ ...base, altScreen: true, trackingLevel: 0b001, kind: "move", button: 0 }),
		).toBeNull();
		expect(
			encodeMouseReport({ ...base, altScreen: true, trackingLevel: 0b010, kind: "move", button: 0 }),
		).toBeNull();
		expect(
			encodeMouseReport({ ...base, altScreen: true, trackingLevel: 0b100, kind: "move", button: 0 }),
		).toBe("\x1b[<35;5;3M");
	});

	it("still reports alt-screen press, release and drag with no tracking mode set", () => {
		const alt = { ...base, altScreen: true, trackingLevel: 0 } as const;
		expect(encodeMouseReport({ ...alt, kind: "press", button: 0 })).toBe("\x1b[<0;5;3M");
		expect(encodeMouseReport({ ...alt, kind: "release", button: 0 })).toBe("\x1b[<0;5;3m");
		expect(encodeMouseReport({ ...alt, kind: "drag", button: 0 })).toBe("\x1b[<32;5;3M");
	});

	it("reports in the normal buffer when the program asked, with no alt screen", () => {
		expect(encodeMouseReport({ ...base, altScreen: false, kind: "press", button: 0 })).toBe(
			"\x1b[<0;5;3M",
		);
	});

	it("reports in the alt screen even with no tracking mode set", () => {
		expect(
			encodeMouseReport({ ...base, altScreen: true, trackingLevel: 0, kind: "press", button: 0 }),
		).toBe("\x1b[<0;5;3M");
	});

	it("returns null for a shift-held event so the user can always select", () => {
		expect(
			encodeMouseReport({
				...base,
				kind: "press",
				button: 0,
				modifiers: { shift: true, alt: false, ctrl: false },
			}),
		).toBeNull();
	});

	it("encodes the wheel with Warp's 64 and 65 at any tracking level", () => {
		expect(encodeMouseReport({ ...base, kind: "wheelUp", button: 0 })).toBe("\x1b[<64;5;3M");
		expect(encodeMouseReport({ ...base, kind: "wheelDown", button: 0 })).toBe("\x1b[<65;5;3M");
	});

	it("returns null for the wheel when no tracking mode is set and no alt screen", () => {
		expect(
			encodeMouseReport({ ...base, trackingLevel: 0, altScreen: false, kind: "wheelUp", button: 0 }),
		).toBeNull();
	});

	it("returns null for a shift-held wheel so the block list scrolls", () => {
		expect(
			encodeMouseReport({
				...base,
				kind: "wheelUp",
				button: 0,
				modifiers: { shift: true, alt: false, ctrl: false },
			}),
		).toBeNull();
	});

	it("adds 8 for alt and 16 for ctrl, and both together", () => {
		expect(
			encodeMouseReport({
				...base,
				kind: "press",
				button: 0,
				modifiers: { shift: false, alt: true, ctrl: false },
			}),
		).toBe("\x1b[<8;5;3M");
		expect(
			encodeMouseReport({
				...base,
				kind: "press",
				button: 2,
				modifiers: { shift: false, alt: false, ctrl: true },
			}),
		).toBe("\x1b[<18;5;3M");
		expect(
			encodeMouseReport({
				...base,
				trackingLevel: 0b010,
				kind: "drag",
				button: 0,
				modifiers: { shift: false, alt: true, ctrl: true },
			}),
		).toBe("\x1b[<56;5;3M");
	});
});
