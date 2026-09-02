import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { editorStyles } from "./styles.js";

describe("editorStyles", () => {
	it("is byte-identical to the published styles.css export", () => {
		const cssPath = join(dirname(fileURLToPath(import.meta.url)), "styles.css");
		const css = readFileSync(cssPath, "utf8").replace(/\n+$/, "");
		expect(editorStyles).toBe(css);
	});

	it("keeps the input line selectable whatever the host does to the body", () => {
		expect(editorStyles).toContain("user-select: text");
		expect(editorStyles).toContain("-webkit-user-select: text");
	});
});
