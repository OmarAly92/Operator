import { afterEach, describe, expect, it, vi } from "vitest";
import {
	defaultTerminalSecretRedaction,
	readStoredTerminalSecretRedaction,
	terminalSecretRedactionStorageKey,
} from "./terminal-secret-redaction";

describe("terminal secret redaction", () => {
	afterEach(() => {
		vi.unstubAllGlobals();
		window.localStorage.clear();
	});

	it("is off unless the stored value is exactly \"1\"", () => {
		expect(defaultTerminalSecretRedaction).toBe(false);
		expect(readStoredTerminalSecretRedaction()).toBe(false);
		window.localStorage.setItem(terminalSecretRedactionStorageKey, "1");
		expect(readStoredTerminalSecretRedaction()).toBe(true);
		window.localStorage.setItem(terminalSecretRedactionStorageKey, "0");
		expect(readStoredTerminalSecretRedaction()).toBe(false);
		window.localStorage.setItem(terminalSecretRedactionStorageKey, "true");
		expect(readStoredTerminalSecretRedaction()).toBe(false);
	});

	it("falls back to the default when storage throws", () => {
		window.localStorage.setItem(terminalSecretRedactionStorageKey, "1");
		expect(readStoredTerminalSecretRedaction()).toBe(true);
		vi.stubGlobal("localStorage", {
			getItem: () => {
				throw new Error("denied");
			},
		});
		expect(readStoredTerminalSecretRedaction()).toBe(defaultTerminalSecretRedaction);
	});
});
