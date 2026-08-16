import { beforeEach, describe, expect, it } from "vitest";
import { applyDocumentSkin } from "./theme";
import { darkSkin } from "../theme/skins/dark";
import { lightSkin } from "../theme/skins/light";

describe("applyDocumentSkin", () => {
	beforeEach(() => {
		document.documentElement.removeAttribute("style");
		document.documentElement.removeAttribute("data-theme");
		document.documentElement.removeAttribute("data-style-theme");
	});

	it("sets the vars and keeps the attributes the stylesheet depends on", () => {
		applyDocumentSkin("orchestrate", "dark");
		const root = document.documentElement;
		expect(root.style.getPropertyValue("--background")).toBe(darkSkin.background);
		expect(root.dataset.theme).toBe("dark");
		expect(root.dataset.styleTheme).toBeUndefined();
	});

	it("switches every var when the appearance changes", () => {
		applyDocumentSkin("orchestrate", "dark");
		applyDocumentSkin("orchestrate", "light");
		const root = document.documentElement;
		expect(root.style.getPropertyValue("--background")).toBe(lightSkin.background);
		expect(root.dataset.theme).toBe("light");
	});
});
