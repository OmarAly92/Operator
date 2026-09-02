import "@testing-library/jest-dom/vitest";
import React from "react";
import { vi } from "vitest";
import "../i18n";

vi.mock("@operator/terminal-react", () => {
	const h = React.createElement;
	const Surface = ({
		altScreenSurface,
		altScreenActive,
	}: {
		altScreenSurface?: React.ReactNode;
		altScreenActive: boolean;
	}) => {
		const showSurface = altScreenActive && altScreenSurface !== undefined;
		return h(
			"div",
			{ "data-testid": "block-terminal-surface", "data-alt-screen-active": altScreenActive ? "true" : "false" },
			h("div", { "data-testid": "block-list", hidden: showSurface, "aria-hidden": showSurface }),
			altScreenSurface !== undefined
				? h(
						"div",
						{ "data-testid": "alt-screen-slot", hidden: !showSurface, "aria-hidden": !showSurface },
						altScreenSurface,
					)
				: null,
		);
	};
	return {
		TerminalSurface: Surface,
		createCompositionTarget: ({ parent }: { parent: HTMLElement }) => {
			const element = document.createElement("textarea");
			element.setAttribute("aria-hidden", "true");
			element.setAttribute("data-terminal-input", "");
			element.tabIndex = -1;
			parent.append(element);
			return {
				element,
				focus: () => element.focus(),
				isComposing: () => false,
				dispose: () => element.remove(),
			};
		},
		warpDarkTheme: {
			ansi: new Array(16).fill("#000000"),
			foreground: "#ffffff",
			background: "#000000",
			cursor: "#00c2ff",
			selection: "rgba(0,0,0,0)",
			blockBackground: "#000000",
			blockBorder: "#616161",
			blockHeaderForeground: "#f1f1f1",
		},
		createTerminalCore: () => ({
			feed: () => undefined,
			snapshot: () => ({
				generation: 0,
				content: new Uint8Array(0),
				rows: new Uint32Array(0),
				runRanges: new Uint32Array(0),
				stylePairs: new Uint32Array(0),
				blocks: new Uint32Array(0),
				blockText: new Uint8Array(0),
			}),
			onChange: () => () => undefined,
			dispose: () => undefined,
		}),
	};
});

// Guard: node-environment vitest projects (no DOM) still route this setup file,
// so only install the DOM stubs when a DOM exists.
if (typeof window !== "undefined") {
	class ResizeObserverStub {
		observe() {}
		unobserve() {}
		disconnect() {}
	}

	Object.defineProperty(window, "ResizeObserver", {
		configurable: true,
		writable: true,
		value: ResizeObserverStub,
	});

	Object.defineProperty(window, "matchMedia", {
		configurable: true,
		writable: true,
		value: (query: string) => ({
			matches: false,
			media: query,
			onchange: null,
			addEventListener: () => undefined,
			removeEventListener: () => undefined,
			addListener: () => undefined,
			removeListener: () => undefined,
			dispatchEvent: () => false,
		}),
	});

	const localStorageStub = (() => {
		const values = new Map<string, string>();
		return {
			clear: () => values.clear(),
			getItem: (key: string) => values.get(key) ?? null,
			removeItem: (key: string) => values.delete(key),
			setItem: (key: string, value: string) => values.set(key, value),
		};
	})();

	Object.defineProperty(window, "localStorage", {
		configurable: true,
		writable: true,
		value: localStorageStub,
	});

	HTMLCanvasElement.prototype.getContext = (() => ({})) as unknown as typeof HTMLCanvasElement.prototype.getContext;

	Element.prototype.hasPointerCapture = (() => false) as typeof Element.prototype.hasPointerCapture;
	Element.prototype.setPointerCapture = (() => undefined) as typeof Element.prototype.setPointerCapture;
	Element.prototype.releasePointerCapture = (() => undefined) as typeof Element.prototype.releasePointerCapture;
	Element.prototype.scrollIntoView = (() => undefined) as typeof Element.prototype.scrollIntoView;

	window.operator = {
		app: {
			getVersion: async () => "0.0.0-test",
			chooseDirectory: async () => null,
			openExternal: async () => undefined,
			scanImportFolder: async ({ path }: { path: string }) => ({ path, repos: [] }),
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
			writeText: async () => undefined,
			readText: async () => "",
		},
		daemon: {
			getStatus: async () => ({ state: "stopped" }),
			start: async () => ({ state: "starting" }),
			stop: async () => ({ state: "stopped" }),
			restart: async () => ({ state: "starting" }),
			onStatus: () => () => undefined,
		},
		telemetry: {
			getBootstrap: async () => null,
		},
		preview: {
			openExternalPreview: async () => undefined,
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
			set: async (settings: { locale: string }) => ({
				locale: settings.locale as "en",
			}),
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
} // end if (typeof window !== "undefined")
