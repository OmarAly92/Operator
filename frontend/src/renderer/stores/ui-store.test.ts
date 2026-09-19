import { describe, expect, test } from "vitest";
import { useUiStore } from "./ui-store";

describe("openMobileSettings", () => {
	test("opens the global settings on the mobile section", () => {
		useUiStore.getState().openMobileSettings();
		expect(useUiStore.getState().settingsModal).toEqual({ scope: "global", section: "mobile" });
	});
});
