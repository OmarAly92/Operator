import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { UPDATE_OPT_IN_ASKED_KEY, UpdateOptInPrompt } from "./UpdateOptInPrompt";

const { getUpdateSettings, setUpdateSettings } = vi.hoisted(() => ({
	getUpdateSettings: vi.fn(),
	setUpdateSettings: vi.fn(),
}));

vi.mock("../lib/bridge", () => ({
	operatorBridge: { updateSettings: { get: getUpdateSettings, set: setUpdateSettings } },
}));

function tauriWindow(): void {
	(window as unknown as { __TAURI_INTERNALS__?: unknown }).__TAURI_INTERNALS__ = { invoke: vi.fn() };
}

function renderPrompt() {
	const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
	render(
		<QueryClientProvider client={queryClient}>
			<UpdateOptInPrompt />
		</QueryClientProvider>,
	);
}

beforeEach(() => {
	getUpdateSettings.mockReset();
	setUpdateSettings.mockReset();
	setUpdateSettings.mockResolvedValue(undefined);
	window.localStorage.clear();
	tauriWindow();
});

describe("UpdateOptInPrompt", () => {
	it("asks once while the native shell still has updates disabled by default", async () => {
		getUpdateSettings.mockResolvedValue({ enabled: false, channel: "latest", nightlyAck: false, feature: null });
		renderPrompt();
		expect(await screen.findByTestId("updates-opt-in")).toBeInTheDocument();
	});

	it("stays hidden outside the native shell", async () => {
		delete (window as unknown as { __TAURI_INTERNALS__?: unknown }).__TAURI_INTERNALS__;
		getUpdateSettings.mockResolvedValue({ enabled: false, channel: "latest", nightlyAck: false, feature: null });
		renderPrompt();
		await waitFor(() => expect(getUpdateSettings).toHaveBeenCalled());
		expect(screen.queryByTestId("updates-opt-in")).not.toBeInTheDocument();
	});

	it("stays hidden when updates are already enabled", async () => {
		getUpdateSettings.mockResolvedValue({ enabled: true, channel: "latest", nightlyAck: false, feature: null });
		renderPrompt();
		await waitFor(() => expect(getUpdateSettings).toHaveBeenCalled());
		expect(screen.queryByTestId("updates-opt-in")).not.toBeInTheDocument();
	});

	it("stays hidden once the user has already been asked", async () => {
		window.localStorage.setItem(UPDATE_OPT_IN_ASKED_KEY, "1");
		renderPrompt();
		await waitFor(() => expect(getUpdateSettings).toHaveBeenCalled());
		expect(screen.queryByTestId("updates-opt-in")).not.toBeInTheDocument();
	});

	it("declining persists disabled defaults and remembers the answer only after the settings write lands", async () => {
		getUpdateSettings.mockResolvedValue({ enabled: false, channel: "latest", nightlyAck: false, feature: null });
		const setItem = vi.spyOn(window.localStorage, "setItem");
		renderPrompt();
		await userEvent.click(await screen.findByTestId("updates-opt-in-decline"));
		await waitFor(() => expect(setItem).toHaveBeenCalledWith(UPDATE_OPT_IN_ASKED_KEY, "1"));
		expect(setUpdateSettings).toHaveBeenCalledWith({ enabled: false, channel: "latest", nightlyAck: false, feature: null });
		expect(setUpdateSettings.mock.invocationCallOrder[0]).toBeLessThan(setItem.mock.invocationCallOrder[0]);
		await waitFor(() => expect(screen.queryByTestId("updates-opt-in")).not.toBeInTheDocument());
		vi.restoreAllMocks();
	});

	it("accepting enables stable-channel updates and remembers the answer", async () => {
		getUpdateSettings.mockResolvedValue({ enabled: false, channel: "latest", nightlyAck: false, feature: null });
		renderPrompt();
		await userEvent.click(await screen.findByTestId("updates-opt-in-accept"));
		await waitFor(() =>
			expect(setUpdateSettings).toHaveBeenCalledWith({ enabled: true, channel: "latest", nightlyAck: false, feature: null }),
		);
		await waitFor(() => expect(window.localStorage.getItem(UPDATE_OPT_IN_ASKED_KEY)).toBe("1"));
	});

	it("does not remember the answer when persisting settings fails so the ask can retry next launch", async () => {
		getUpdateSettings.mockResolvedValue({ enabled: false, channel: "latest", nightlyAck: false, feature: null });
		setUpdateSettings.mockRejectedValue(new Error("settings write failed"));
		const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
		renderPrompt();
		await userEvent.click(await screen.findByTestId("updates-opt-in-decline"));
		await waitFor(() => expect(warn).toHaveBeenCalledWith("Unable to persist the auto-update opt-in choice", expect.any(Error)));
		expect(setUpdateSettings).toHaveBeenCalledTimes(1);
		expect(window.localStorage.getItem(UPDATE_OPT_IN_ASKED_KEY)).toBeNull();
		vi.restoreAllMocks();
	});

	it("still records the choice when the asked-flag cannot be stored; the prompt re-asks next launch", async () => {
		getUpdateSettings.mockResolvedValue({ enabled: false, channel: "latest", nightlyAck: false, feature: null });
		vi.spyOn(window.localStorage, "setItem").mockImplementation(() => {
			throw new Error("storage blocked");
		});
		renderPrompt();
		await userEvent.click(await screen.findByTestId("updates-opt-in-decline"));
		await waitFor(() =>
			expect(setUpdateSettings).toHaveBeenCalledWith({ enabled: false, channel: "latest", nightlyAck: false, feature: null }),
		);
		expect(window.localStorage.getItem(UPDATE_OPT_IN_ASKED_KEY)).toBeNull();
		vi.restoreAllMocks();
	});
});
