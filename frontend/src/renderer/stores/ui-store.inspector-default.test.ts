import { afterEach, describe, expect, it, vi } from "vitest";

async function loadStore() {
	vi.resetModules();
	return await import("./ui-store");
}

afterEach(() => {
	window.localStorage.clear();
});

describe("ui-store inspector default", () => {
	it("keeps the inspector closed for a session that has never been opened", async () => {
		const { inspectorState } = await loadStore();
		expect(inspectorState({}, "session-1").isOpen).toBe(false);
	});

	it("honours a stored preference to keep it open", async () => {
		window.localStorage.setItem("opr.inspector.open", "true");
		const { inspectorState } = await loadStore();
		expect(inspectorState({}, "session-1").isOpen).toBe(true);
	});

	it("honours a stored preference to keep it closed", async () => {
		window.localStorage.setItem("opr.inspector.open", "false");
		const { inspectorState } = await loadStore();
		expect(inspectorState({}, "session-1").isOpen).toBe(false);
	});

	it("carries the last toggle to sessions opened afterwards", async () => {
		const { inspectorState, useUiStore } = await loadStore();
		useUiStore.getState().toggleInspector("session-1");

		expect(window.localStorage.getItem("opr.inspector.open")).toBe("true");
		expect(inspectorState(useUiStore.getState().inspectorSessions, "session-2").isOpen).toBe(true);
	});
});
