import { describe, expect, it } from "vitest";
import { headingIndexBeforeLine } from "./markdown-scroll-sync";

const doc = [
	"---",
	"title: \"Search page\"",
	"---",
	"",
	"# Spec",
	"",
	"Intro.",
	"",
	"## Goals",
	"",
	"```md",
	"# not a heading",
	"```",
	"",
	"### Details",
	"text",
].join("\n");

describe("headingIndexBeforeLine", () => {
	it("returns -1 before the first heading and inside the frontmatter", () => {
		expect(headingIndexBeforeLine(doc, 1)).toBe(-1);
		expect(headingIndexBeforeLine(doc, 4)).toBe(-1);
	});

	it("returns the index of the last heading at or before the line", () => {
		expect(headingIndexBeforeLine(doc, 5)).toBe(0);
		expect(headingIndexBeforeLine(doc, 7)).toBe(0);
		expect(headingIndexBeforeLine(doc, 9)).toBe(1);
		expect(headingIndexBeforeLine(doc, 15)).toBe(2);
		expect(headingIndexBeforeLine(doc, 99)).toBe(2);
	});

	it("ignores headings inside fenced code", () => {
		expect(headingIndexBeforeLine(doc, 12)).toBe(1);
	});
});
