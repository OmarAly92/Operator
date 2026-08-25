import type { OperatorBridge } from "../../shared/operator-bridge";
import { invoke as tauriInvoke } from "@tauri-apps/api/core";
import { listen as tauriListen } from "@tauri-apps/api/event";
import { coerceLocale } from "../../shared/ui-locale";
import type { FeatureBuild } from "../../shared/feature-builds";
import { createTauriBridge } from "./tauri-bridge";

export type { FeatureBuild };

export function createWindowBridge(windowBridge: OperatorBridge | undefined): OperatorBridge {
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
				message: "The desktop bridge is not available in browser preview.",
			}),
			start: async () => ({ state: "starting" }),
			stop: async () => ({ state: "stopped" }),
			restart: async () => ({ state: "starting" }),
			onStatus: () => () => undefined,
		},
		telemetry: {
			getBootstrap: async () => null,
		},
		preview: {
			openExternalPreview: async ({ url }) => {
				window.open(url, "_blank", "noopener,noreferrer");
			},
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

export const tauriInternalsPresent = (): boolean =>
	Boolean((window as { __TAURI_INTERNALS__?: unknown }).__TAURI_INTERNALS__);

export const nativeShellBridgePresent = (): boolean => Boolean(window.operator) || tauriInternalsPresent();

function selectShellBridge(): OperatorBridge {
	if (window.operator) return createWindowBridge(window.operator);
	if (tauriInternalsPresent()) {
		const invoke: (command: string, payload?: unknown) => Promise<unknown> = (command, payload) =>
			tauriInvoke(command, payload as never);
		const tauriBridge = createTauriBridge({
			invoke,
			listen: (eventName, handler) => tauriListen(eventName, handler as never),
		});
		return tauriBridge as OperatorBridge;
	}
	return createWindowBridge(undefined);
}

export async function selectShellBridgeForTest(): Promise<OperatorBridge> {
	return selectShellBridge();
}

export const operatorBridge: OperatorBridge = selectShellBridge();
