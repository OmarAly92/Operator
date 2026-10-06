import { afterEach, describe, expect, it, vi } from "vitest";
import {
	defaultTerminalPredictiveEcho,
	readStoredTerminalPredictiveEcho,
	terminalPredictiveEchoStorageKey,
	terminalPredictiveEchoThresholdMs,
} from "./terminal-predictive-echo";

describe("terminal predictive echo", () => {
	afterEach(() => {
		vi.unstubAllGlobals();
		window.localStorage.clear();
	});

	it("is off unless the stored value is exactly \"1\"", () => {
		expect(defaultTerminalPredictiveEcho).toBe(false);
		expect(readStoredTerminalPredictiveEcho()).toBe(false);
		window.localStorage.setItem(terminalPredictiveEchoStorageKey, "1");
		expect(readStoredTerminalPredictiveEcho()).toBe(true);
		window.localStorage.setItem(terminalPredictiveEchoStorageKey, "0");
		expect(readStoredTerminalPredictiveEcho()).toBe(false);
		window.localStorage.setItem(terminalPredictiveEchoStorageKey, "true");
		expect(readStoredTerminalPredictiveEcho()).toBe(false);
	});

	it("falls back to the default when storage throws", () => {
		window.localStorage.setItem(terminalPredictiveEchoStorageKey, "1");
		expect(readStoredTerminalPredictiveEcho()).toBe(true);
		vi.stubGlobal("localStorage", {
			getItem: () => {
				throw new Error("denied");
			},
		});
		expect(readStoredTerminalPredictiveEcho()).toBe(defaultTerminalPredictiveEcho);
	});

	it("arms above a loopback round trip and below a tunnelled one", () => {
		expect(terminalPredictiveEchoThresholdMs).toBeGreaterThan(7);
		expect(terminalPredictiveEchoThresholdMs).toBeLessThan(107);
	});
});
