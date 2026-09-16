import { beforeEach, describe, expect, it, vi } from "vitest";

const getKeybindings = vi.fn();

vi.mock("../lib/bridge", () => ({
	operatorBridge: {
		keybindings: {
			get: (...args: unknown[]) => getKeybindings(...args),
			set: vi.fn(),
		},
	},
}));

import { useKeybindingsStore } from "./keybindings-store";

describe("keybindings-store", () => {
	beforeEach(() => {
		getKeybindings.mockReset();
		useKeybindingsStore.setState({ overrides: {}, loaded: false });
	});

	it("resolves without throwing when the daemon is not ready and retries on the next load", async () => {
		getKeybindings.mockRejectedValueOnce(new Error("Operator daemon is starting."));
		await expect(useKeybindingsStore.getState().load()).resolves.toBeUndefined();
		expect(useKeybindingsStore.getState().loaded).toBe(false);

		getKeybindings.mockResolvedValue({ "session.new": [{ key: "n", mod: true }] });
		await useKeybindingsStore.getState().load();
		expect(getKeybindings).toHaveBeenCalledTimes(2);
		expect(useKeybindingsStore.getState()).toMatchObject({
			overrides: { "session.new": [{ key: "n", mod: true }] },
			loaded: true,
		});
	});

	it("does not reload after the first successful load", async () => {
		getKeybindings.mockResolvedValue({});
		await useKeybindingsStore.getState().load();
		await useKeybindingsStore.getState().load();
		expect(getKeybindings).toHaveBeenCalledTimes(1);
	});
});
