import { afterEach, describe, expect, it, vi } from "vitest";
import { claimOnScreenTerminals, isTerminalOnScreen, terminalShownInAPane } from "./on-screen-terminals";

afterEach(() => vi.restoreAllMocks());

function focusedAndVisible(visible: DocumentVisibilityState, focused: boolean) {
	vi.spyOn(document, "visibilityState", "get").mockReturnValue(visible);
	vi.spyOn(document, "hasFocus").mockReturnValue(focused);
}

describe("on-screen terminals", () => {
	it("counts a terminal as shown while any claim holds it and forgets it on release", () => {
		const releaseA = claimOnScreenTerminals(["h1", "h2"]);
		const releaseB = claimOnScreenTerminals(["h2"]);
		expect(terminalShownInAPane("h1")).toBe(true);
		releaseA();
		expect(terminalShownInAPane("h1")).toBe(false);
		expect(terminalShownInAPane("h2")).toBe(true);
		releaseB();
		expect(terminalShownInAPane("h2")).toBe(false);
	});

	it("is on screen only in a visible, focused window", () => {
		const release = claimOnScreenTerminals(["h1"]);
		focusedAndVisible("visible", true);
		expect(isTerminalOnScreen("h1")).toBe(true);
		expect(isTerminalOnScreen("h9")).toBe(false);
		vi.restoreAllMocks();
		focusedAndVisible("visible", false);
		expect(isTerminalOnScreen("h1")).toBe(false);
		vi.restoreAllMocks();
		focusedAndVisible("hidden", true);
		expect(isTerminalOnScreen("h1")).toBe(false);
		release();
	});
});
