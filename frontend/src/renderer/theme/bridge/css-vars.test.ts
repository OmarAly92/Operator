import { describe, expect, it } from "vitest";
import { applySkinVars, skinToCssVars } from "./css-vars";
import { darkSkin } from "../skins/dark";

describe("skinToCssVars", () => {
	it("emits one entry per slot, keyed by CSS variable name", () => {
		const vars = skinToCssVars(darkSkin);
		expect(Object.keys(vars).length).toBe(231);
		expect(vars["--color-status-working"]).toBe(darkSkin.statusWorking);
	});

	it("applies every variable to the element", () => {
		const root = document.createElement("div");
		applySkinVars(darkSkin, root);
		expect(root.style.getPropertyValue("--color-status-working")).toBe(darkSkin.statusWorking);
		expect(root.style.getPropertyValue("--background")).toBe(darkSkin.background);
	});
});
