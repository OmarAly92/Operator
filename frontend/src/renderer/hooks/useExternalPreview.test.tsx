import { act, renderHook, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useExternalPreview } from "./useExternalPreview";

const openExternalPreviewMock = vi.hoisted(() => vi.fn(async () => undefined));
const openExternalMock = vi.hoisted(() => vi.fn(async (_url: string) => undefined));
const fetchMock = vi.hoisted(() => vi.fn());
const bridgeRef = vi.hoisted(() => ({ current: undefined as Record<string, unknown> | undefined }));

vi.mock("../lib/bridge", () => ({
	get operatorBridge() {
		return bridgeRef.current;
	},
}));

vi.mock("../lib/api-client", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../lib/api-client")>();
	return {
		...actual,
		getApiBaseUrl: () => "http://127.0.0.1:3001",
		hasTrustedApiBaseUrl: () => true,
	};
});

type BridgeOverrides = {
	preview?: unknown;
};

function setBridge(overrides: BridgeOverrides = {}) {
	bridgeRef.current = {
		app: {
			openExternal: openExternalMock,
			getVersion: async () => "0.0.0-test",
		},
		terminal: { saveDroppedFile: async () => "" },
		window: { setOverlay: async () => undefined, isFullScreen: async () => false, onFullScreen: () => () => undefined },
		theme: { set: async () => undefined },
		menu: { action: async () => undefined, notifyShellFocus: () => undefined },
		clipboard: { writeText: async () => undefined, readText: async () => "" },
		daemon: { getStatus: async () => ({ state: "stopped" }), onStatus: () => () => undefined },
		telemetry: { getBootstrap: async () => null },
		notifications: { show: async () => undefined, setBadge: async () => undefined, devBounce: async () => undefined, onClick: () => () => undefined },
		tray: { setAttentionState: () => undefined, onOpenSession: () => () => undefined },
		appState: { getMigration: async () => ({ status: "pending" }), setMigration: async () => undefined },
		updateSettings: { get: async () => ({ enabled: false, channel: "latest", nightlyAck: false, feature: null }), set: async () => undefined },
		uiSettings: { get: async () => ({ locale: "en" as const }), set: async (settings: { locale: string }) => ({ locale: settings.locale as "en" }) },
		keybindings: { get: async () => ({}), set: async (overrides: unknown) => overrides, setRecording: async () => undefined },
		updates: {
			getStatus: async () => ({ state: "idle" }),
			check: async () => undefined,
			returnHome: async () => undefined,
			download: async () => undefined,
			install: async () => undefined,
			onStatus: () => () => undefined,
			onTelemetry: () => () => undefined,
		},
		featureBuilds: { list: async () => [], getActive: async () => null },
		preview: "preview" in overrides ? overrides.preview : { openExternalPreview: openExternalPreviewMock },
	};
}

type RenderOptions = {
	sessionId?: string;
	previewUrl?: string;
	previewRevision?: number;
	previewOpenedRevision?: number;
	terminated?: boolean;
};

function renderPreview(options: RenderOptions) {
	return renderHook((next: RenderOptions = options) => useExternalPreview(next), {
		initialProps: options,
	});
}

describe("useExternalPreview", () => {
	beforeEach(() => {
		openExternalPreviewMock.mockClear().mockResolvedValue(undefined);
		openExternalMock.mockClear().mockResolvedValue(undefined);
		fetchMock.mockClear().mockResolvedValue({ ok: true });
		vi.stubGlobal("fetch", fetchMock);
		setBridge();
	});

	afterEach(() => {
		vi.unstubAllGlobals();
		bridgeRef.current = undefined;
	});

	it("auto-opens a new non-empty revision exactly once", async () => {
		const view = renderPreview({ sessionId: "mer-1", previewUrl: "http://localhost:5173/", previewRevision: 3 });
		await waitFor(() => expect(openExternalPreviewMock).toHaveBeenCalledTimes(1));
		expect(openExternalPreviewMock).toHaveBeenCalledWith({
			sessionId: "mer-1",
			url: "http://localhost:5173/",
			revision: 3,
		});

		view.rerender({ sessionId: "mer-1", previewUrl: "http://localhost:5173/", previewRevision: 3 });
		await act(async () => undefined);
		expect(openExternalPreviewMock).toHaveBeenCalledTimes(1);
	});

	it("does not reopen an acknowledged revision after a rerender or remount", async () => {
		const view = renderPreview({
			sessionId: "mer-1",
			previewUrl: "http://localhost:5173/",
			previewRevision: 3,
			previewOpenedRevision: 3,
		});
		await act(async () => undefined);
		view.rerender({
			sessionId: "mer-1",
			previewUrl: "http://localhost:5173/",
			previewRevision: 3,
			previewOpenedRevision: 3,
		});
		await act(async () => undefined);
		view.unmount();

		renderPreview({
			sessionId: "mer-1",
			previewUrl: "http://localhost:5173/",
			previewRevision: 3,
			previewOpenedRevision: 3,
		});
		await act(async () => undefined);
		expect(openExternalPreviewMock).not.toHaveBeenCalled();
	});

	it("opens a pending revision once after a restart", async () => {
		renderPreview({
			sessionId: "mer-1",
			previewUrl: "http://localhost:5173/",
			previewRevision: 5,
			previewOpenedRevision: 3,
		});
		await waitFor(() => expect(openExternalPreviewMock).toHaveBeenCalledTimes(1));
		expect(openExternalPreviewMock).toHaveBeenCalledWith({
			sessionId: "mer-1",
			url: "http://localhost:5173/",
			revision: 5,
		});
	});

	it("opens again when a later revision arrives", async () => {
		const view = renderPreview({ sessionId: "mer-1", previewUrl: "http://localhost:5173/", previewRevision: 3 });
		await waitFor(() => expect(openExternalPreviewMock).toHaveBeenCalledTimes(1));

		view.rerender({ sessionId: "mer-1", previewUrl: "http://localhost:5173/", previewRevision: 4 });
		await waitFor(() => expect(openExternalPreviewMock).toHaveBeenCalledTimes(2));
		expect(openExternalPreviewMock).toHaveBeenLastCalledWith({
			sessionId: "mer-1",
			url: "http://localhost:5173/",
			revision: 4,
		});
	});

	it("clear opens nothing", async () => {
		const view = renderPreview({ sessionId: "mer-1", previewUrl: "http://localhost:3000/", previewRevision: 1 });
		await waitFor(() => expect(openExternalPreviewMock).toHaveBeenCalledTimes(1));

		view.rerender({ sessionId: "mer-1", previewUrl: "", previewRevision: 2 });
		await act(async () => undefined);
		expect(openExternalPreviewMock).toHaveBeenCalledTimes(1);
	});

	it("rejects invalid schemes without invoking the opener", async () => {
		for (const target of ["file:///etc/passwd", "javascript:alert(1)", "mailto:user@example.com"]) {
			renderPreview({ sessionId: "mer-1", previewUrl: target, previewRevision: 1 });
			await act(async () => undefined);
			expect(openExternalPreviewMock).not.toHaveBeenCalled();
		}
	});

	it("opens nothing for a terminated session with a stale target", async () => {
		renderPreview({
			sessionId: "mer-1",
			previewUrl: "http://localhost:5173/",
			previewRevision: 2,
			terminated: true,
		});
		await act(async () => undefined);
		expect(openExternalPreviewMock).not.toHaveBeenCalled();
	});

	it("surfaces a retryable message when the opener fails and retries on demand", async () => {
		openExternalPreviewMock.mockRejectedValueOnce(new Error("opener unavailable"));
		const view = renderPreview({ sessionId: "mer-1", previewUrl: "http://localhost:5173/", previewRevision: 3 });
		await waitFor(() => expect(view.result.current.error).toContain("default browser"));

		act(() => {
			view.result.current.retry();
		});
		await waitFor(() => expect(openExternalPreviewMock).toHaveBeenCalledTimes(2));
		await waitFor(() => expect(view.result.current.error).toBe(""));
	});

	it("manual reopen validates HTTP(S), invokes the opener, and never acknowledges", async () => {
		const view = renderPreview({ sessionId: "mer-1" });

		await act(async () => {
			await view.result.current.reopen("https://preview.example.dev/app");
		});
		expect(openExternalMock).toHaveBeenCalledWith("https://preview.example.dev/app");
		expect(openExternalPreviewMock).not.toHaveBeenCalled();
		expect(fetchMock).not.toHaveBeenCalled();

		openExternalMock.mockClear();
		await act(async () => {
			await view.result.current.reopen("file:///etc/passwd");
		});
		expect(openExternalMock).not.toHaveBeenCalled();
		expect(view.result.current.error).toContain("HTTP");
	});

	it("falls back to the shell opener plus an explicit ack when the bridge lacks a preview namespace", async () => {
		setBridge({ preview: undefined });
		const view = renderPreview({ sessionId: "mer-1", previewUrl: "http://localhost:5173/", previewRevision: 6 });
		await waitFor(() => expect(openExternalMock).toHaveBeenCalledWith("http://localhost:5173/"));
		await waitFor(() => expect(fetchMock).toHaveBeenCalled());
		const [ackUrl, ackInit] = fetchMock.mock.calls[0];
		expect(String(ackUrl)).toBe("http://127.0.0.1:3001/internal/desktop/sessions/mer-1/preview-opened");
		expect((ackInit as RequestInit).method).toBe("POST");
		expect(JSON.parse(String((ackInit as RequestInit).body))).toEqual({ revision: 6 });
		expect(view.result.current.error).toBe("");
	});

	it("acknowledges only after the fallback opener succeeds", async () => {
		setBridge({ preview: undefined });
		openExternalMock.mockRejectedValueOnce(new Error("no default browser"));
		renderPreview({ sessionId: "mer-1", previewUrl: "http://localhost:5173/", previewRevision: 6 });
		await waitFor(() => expect(fetchMock).not.toHaveBeenCalled());
	});
});
