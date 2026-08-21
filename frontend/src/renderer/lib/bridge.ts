import type { OperatorBridge } from "../../shared/operator-bridge";
import { coerceLocale } from "../../shared/ui-locale";
import type { FeatureBuild } from "../../shared/feature-builds";

export type { FeatureBuild };

export function createElectronBridge(windowBridge: OperatorBridge | undefined): OperatorBridge {
	if (windowBridge) return windowBridge;
	return createBrowserPreviewBridge();
}

function createBrowserPreviewBridge(): OperatorBridge {
	return {
		app: {
			getVersion: async () => "0.0.0-preview",
			chooseDirectory: async () => null,
			openExternal: async (url: string) => {
				window.open(url, "_blank", "noopener,noreferrer");
			},
			scanImportFolder: async ({ path }) => ({ path, repos: [] }),
			checkAncestorRepo: async () => undefined,
			onNewSessionShortcut: () => () => undefined,
			onKeyboardShortcutsHelp: () => () => undefined,
			onNewShellTerminalShortcut: () => () => undefined,
			onCloseShellTerminalShortcut: () => () => undefined,
			setCloseShellTerminalShortcutEnabled: () => undefined,
			onOpenSettingsShortcut: () => () => undefined,
			onPreviousSessionShortcut: () => () => undefined,
			onNextSessionShortcut: () => () => undefined,
			onPreviousTabShortcut: () => () => undefined,
			onNextTabShortcut: () => () => undefined,
			onFocusTerminalShortcut: () => () => undefined,
		},
		terminal: {
			saveDroppedFile: async () => "",
		},
		window: {
			setOverlay: async () => undefined,
			isFullScreen: async () => false,
			onFullScreen: () => () => undefined,
		},
		theme: {
			set: async () => undefined,
		},
		menu: {
			action: async () => undefined,
			notifyShellFocus: () => undefined,
		},
		clipboard: {
			writeText: async (text: string) => {
				if (navigator.clipboard?.writeText) {
					await navigator.clipboard.writeText(text);
				}
			},
			readText: async () => (navigator.clipboard?.readText ? navigator.clipboard.readText() : ""),
		},
		daemon: {
			getStatus: async () => ({
				state: "stopped",
				message: "Electron preload is not available in browser preview.",
			}),
			start: async () => ({ state: "starting" }),
			stop: async () => ({ state: "stopped" }),
			restart: async () => ({ state: "starting" }),
			onStatus: () => () => undefined,
		},
		telemetry: {
			getBootstrap: async () => null,
		},
		browser: {
			nativeCompositionEnabled: false,
			ensure: async (sessionId: string) => ({
				viewId: `preview:${sessionId}`,
				url: "",
				title: "",
				canGoBack: false,
				canGoForward: false,
				isLoading: false,
			}),
			setBounds: () => undefined,
			setOverlayOpen: () => undefined,
			navigate: async ({ viewId, url }) => ({
				viewId,
				url,
				title: "",
				canGoBack: false,
				canGoForward: false,
				isLoading: false,
			}),
			clear: async (viewId: string) => ({
				viewId,
				url: "",
				title: "",
				canGoBack: false,
				canGoForward: false,
				isLoading: false,
			}),
			goBack: async (viewId: string) => ({
				viewId,
				url: "",
				title: "",
				canGoBack: false,
				canGoForward: false,
				isLoading: false,
			}),
			goForward: async (viewId: string) => ({
				viewId,
				url: "",
				title: "",
				canGoBack: false,
				canGoForward: false,
				isLoading: false,
			}),
			reload: async (viewId: string) => ({
				viewId,
				url: "",
				title: "",
				canGoBack: false,
				canGoForward: false,
				isLoading: false,
			}),
			stop: async (viewId: string) => ({
				viewId,
				url: "",
				title: "",
				canGoBack: false,
				canGoForward: false,
				isLoading: false,
			}),
			getTabs: async (viewId: string) => ({ viewId, activeTabId: "t1", tabs: [] }),
			selectTab: async ({ viewId, tabId }) => ({ viewId, activeTabId: tabId, tabs: [] }),
			closeTab: async ({ viewId }) => ({ viewId, activeTabId: "", tabs: [] }),
			openTab: async ({ viewId }) => ({ viewId, activeTabId: "", tabs: [] }),
			devtools: async ({ viewId, operation }) => ({
				viewId,
				open: operation !== "close",
				activeTabId: "",
			}),
			destroy: () => undefined,
			setAnnotationMode: async () => undefined,
			onNavState: () => () => undefined,
			onTabsState: () => () => undefined,
			onAgentActivity: () => () => undefined,
			onDevToolsState: () => () => undefined,
			onAnnotationSubmit: () => () => undefined,
			onAnnotationCancel: () => () => undefined,
		},
		notifications: {
			show: async () => undefined,
			setBadge: async () => undefined,
			devBounce: async () => undefined,
			onClick: () => () => undefined,
		},
		tray: {
			setAttentionState: () => undefined,
			onOpenSession: () => () => undefined,
		},
		appState: {
			getMigration: async () => ({ status: "pending" }),
			setMigration: async () => undefined,
		},
		updateSettings: {
			get: async () => ({ enabled: false, channel: "latest", nightlyAck: false, feature: null }),
			set: async () => undefined,
		},
		uiSettings: {
			get: async () => ({ locale: "en" as const }),
			set: async (settings) => ({ locale: coerceLocale(settings.locale) }),
		},
		keybindings: {
			get: async () => ({}),
			set: async (overrides) => overrides,
			setRecording: async () => undefined,
		},
		updates: {
			getStatus: async () => ({ state: "idle" }),
			check: async () => undefined,
			returnHome: async () => undefined,
			download: async () => undefined,
			install: async () => undefined,
			onStatus: () => () => undefined,
			onTelemetry: () => () => undefined,
		},
		featureBuilds: {
			list: async () => [],
			getActive: async () => null,
		},
	};
}

const tauriInternalsPresent = (): boolean =>
	Boolean((window as { __TAURI_INTERNALS__?: unknown }).__TAURI_INTERNALS__);

async function selectShellBridge(): Promise<OperatorBridge> {
	if (window.operator) return createElectronBridge(window.operator);
	if (tauriInternalsPresent()) {
		const { createTauriBridge } = await import("./tauri-bridge");
		const core = await import("@tauri-apps/api/core");
		const event = await import("@tauri-apps/api/event");
		const invoke: (command: string, payload?: unknown) => Promise<unknown> = (command, payload) =>
			core.invoke(command, payload as never);
		const unlisteners = new Map<(event: { payload: unknown }) => void, () => void>();
		const tauriBridge = createTauriBridge({
			invoke,
			listen: (eventName, handler) => {
				let disposed = false;
				void event
					.listen(eventName, handler as never)
					.then((unlisten) => {
						if (disposed) unlisten();
						else unlisteners.set(handler, unlisten);
					})
					.catch(() => {
						unlisteners.delete(handler);
					});
				return () => {
					disposed = true;
					const dispose = unlisteners.get(handler);
					unlisteners.delete(handler);
					dispose?.();
				};
			},
		});
		return tauriBridge as OperatorBridge;
	}
	return createElectronBridge(undefined);
}

const bridgePromise: Promise<OperatorBridge> = selectShellBridge();

let resolvedBridge: OperatorBridge | null = null;
void bridgePromise.then((bridge) => {
	resolvedBridge = bridge;
});

export async function selectShellBridgeForTest(): Promise<OperatorBridge> {
	return bridgePromise;
}

export const operatorBridge: OperatorBridge = new Proxy(createBrowserPreviewBridge(), {
	get(_target, property, receiver) {
		if (window.operator) return Reflect.get(window.operator, property);
		if (resolvedBridge) return Reflect.get(resolvedBridge as object, property, receiver);
		return Reflect.get(_target as object, property, receiver);
	},
});
