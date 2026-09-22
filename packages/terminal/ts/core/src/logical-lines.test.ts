import { describe, expect, it } from "vitest";
import { joinLogicalLine } from "./logical-lines";

describe("joinLogicalLine", () => {
	it("joins the pieces verbatim and records where each row starts", () => {
		expect(joinLogicalLine(["abc ", "def"])).toEqual({ text: "abc def", rowOffsets: [0, 4] });
		expect(joinLogicalLine(["漢字", "x"])).toEqual({ text: "漢字x", rowOffsets: [0, 2] });
		expect(joinLogicalLine(["only"])).toEqual({ text: "only", rowOffsets: [0] });
	});
});
