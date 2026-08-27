import { describe, expect, it } from "vitest";
import {
	headerSticks,
	isPinned,
	nextBoundary,
	previousBoundary,
	previousTarget,
	topItemFor,
} from "./block-viewport";

const items = [
	{ index: 0, start: 0, size: 100 },
	{ index: 1, start: 100, size: 250 },
	{ index: 2, start: 350, size: 80 },
];

describe("topItemFor", () => {
	it("finds the item spanning the top edge", () => {
		expect(topItemFor(items, 0)?.index).toBe(0);
		expect(topItemFor(items, 99)?.index).toBe(0);
		expect(topItemFor(items, 100)?.index).toBe(1);
		expect(topItemFor(items, 349)?.index).toBe(1);
		expect(topItemFor(items, 350)?.index).toBe(2);
	});

	it("returns nothing past the end of what is rendered", () => {
		expect(topItemFor(items, 430)).toBeUndefined();
	});

	it("returns nothing for an empty window", () => {
		expect(topItemFor([], 0)).toBeUndefined();
	});
});

describe("headerSticks", () => {
	it("sticks for a block shorter than the viewport", () => {
		expect(headerSticks(200, 600)).toBe(true);
	});

	it("sticks for a block exactly as tall as the viewport", () => {
		expect(headerSticks(600, 600)).toBe(true);
	});

	it("does not stick for a block taller than the viewport", () => {
		expect(headerSticks(900, 600)).toBe(false);
	});

	it("does not stick when the viewport has no height yet", () => {
		expect(headerSticks(100, 0)).toBe(false);
	});
});

describe("isPinned", () => {
	it("is pinned at the tail and inside the slack", () => {
		expect(isPinned(400, 1000, 600)).toBe(true);
		expect(isPinned(380, 1000, 600)).toBe(true);
	});

	it("is not pinned once clear of the slack", () => {
		expect(isPinned(300, 1000, 600)).toBe(false);
	});

	it("a list shorter than its viewport is pinned", () => {
		expect(isPinned(0, 200, 600)).toBe(true);
	});
});

describe("boundaries", () => {
	it("steps forward and stops at the last block", () => {
		expect(nextBoundary(0, 3)).toBe(1);
		expect(nextBoundary(2, 3)).toBeUndefined();
	});

	it("steps forward from nothing to the first block", () => {
		expect(nextBoundary(undefined, 3)).toBe(0);
	});

	it("steps back and stops at the first block", () => {
		expect(previousBoundary(2, 3)).toBe(1);
		expect(previousBoundary(0, 3)).toBeUndefined();
	});

	it("has no boundary in an empty list", () => {
		expect(nextBoundary(undefined, 0)).toBeUndefined();
		expect(previousBoundary(0, 0)).toBeUndefined();
	});
});

describe("previousTarget", () => {
	it("returns to the start of a partly scrolled block first", () => {
		expect(previousTarget({ index: 1, start: 100, size: 250 }, 180, 3)).toBe(1);
	});

	it("steps to the block before once already at a boundary", () => {
		expect(previousTarget({ index: 1, start: 100, size: 250 }, 100, 3)).toBe(0);
	});

	it("has nowhere to go from the first block's start", () => {
		expect(previousTarget({ index: 0, start: 0, size: 100 }, 0, 3)).toBeUndefined();
	});

	it("has nowhere to go with no top item", () => {
		expect(previousTarget(undefined, 0, 3)).toBeUndefined();
	});
});
