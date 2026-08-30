import { describe, expect, it } from "vitest";
import { clampPriority, optHasName } from "./signature.js";

describe("clampPriority", () => {
	it("defaults to zero", () => {
		expect(clampPriority(undefined)).toBe(0);
	});

	it("clamps to Warp's [-100, 100] range", () => {
		expect(clampPriority(500)).toBe(100);
		expect(clampPriority(-500)).toBe(-100);
		expect(clampPriority(37)).toBe(37);
	});
});

describe("optHasName", () => {
	const opt = { name: ["-f", "--force"] };

	it("matches a long name without its hyphens", () => {
		expect(optHasName(opt, "force")).toBe(true);
	});

	it("matches a short name without its hyphen", () => {
		expect(optHasName(opt, "f")).toBe(true);
	});

	it("does not match a name that was never declared", () => {
		expect(optHasName(opt, "quiet")).toBe(false);
	});

	it("does not match when the caller leaves the hyphens on", () => {
		expect(optHasName(opt, "--force")).toBe(false);
	});
});
