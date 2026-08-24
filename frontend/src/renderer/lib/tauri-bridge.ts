import type { components } from "../../api/schema";
import type { DaemonStatus } from "../../shared/daemon-status";
import type { MigrationState } from "../../shared/app-state";
import type { UpdateSettings, UpdateStatus } from "../../shared/update-settings";
import type { UiSettings } from "../../shared/ui-locale";
import { coerceLocale } from "../../shared/ui-locale";
import type { FeatureBuild } from "../../shared/feature-builds";
import type { ImportFolderScan } from "../../shared/import-folder-scan";
import type { TrayAttentionState, TrayOpenSessionTarget } from "../../shared/tray";
import type { KeybindingOverrides } from "../../shared/shortcuts";
import type { TelemetryBootstrap } from "../../shared/telemetry";
import type { UpdateOutcome } from "../../shared/update-telemetry";
import type { ExternalPreviewOpenInput, OperatorBridge } from "../../shared/operator-bridge";
import { apiClient, apiErrorMessage, getApiBaseUrl, hasTrustedApiBaseUrl, subscribeApiBaseUrl } from "./api-client";
import { isAllowedPreviewUrl } from "./preview-url";

type SettingsPayload = components["schemas"]["SettingsResponse"];

const PENDING_MIGRATION: MigrationState = { status: "pending" };
const DEFAULT_UPDATE_SETTINGS: UpdateSettings = {
	enabled: false,
	channel: "latest",
	nightlyAck: false,
	feature: null,
};
const BOOTSTRAP_BASE_URL_TIMEOUT_MS = 10_000;
const BASE64_CHUNK_SIZE = 0x8000;

/** Encodes raw dropped-file bytes as base64 so they survive Tauri's JSON IPC. */
export function encodeBase64(bytes: Uint8Array): string {
	let binary = "";
	for (let offset = 0; offset < bytes.length; offset += BASE64_CHUNK_SIZE) {
		const chunk = bytes.subarray(offset, offset + BASE64_CHUNK_SIZE);
		binary += String.fromCharCode(...chunk);
	}
	if (typeof btoa === "function") return btoa(binary);
	return Buffer.from(bytes).toString("base64");
}

function applyTrayLocale(invoke: TauriBridgeTransports["invoke"], locale: string): void {
	void Promise.resolve(invoke("tray_set_locale", { locale })).catch(() => undefined);
}

/**
 * Resolves once the daemon port is known, or null if that does not happen
 * within timeoutMs — initTelemetry runs before the shell loader reports daemon
 * readiness, and without this first call would race the handshake and disable
 * telemetry for the whole session.
 */
async function waitForTrustedApiBaseUrl(timeoutMs: number): Promise<string | null> {
	if (hasTrustedApiBaseUrl()) return getApiBaseUrl();
	return new Promise((resolve) => {
		const finish = (baseUrl: string | null) => {
			clearTimeout(timer);
			unsubscribe();
			resolve(baseUrl);
		};
		const timer = setTimeout(() => finish(null), timeoutMs);
		const unsubscribe = subscribeApiBaseUrl(() => {
			if (hasTrustedApiBaseUrl()) finish(getApiBaseUrl());
		});
	});
}

/** Parses the wire shape, treating anything unusable as a withheld bootstrap. */
export function parseTelemetryBootstrap(payload: unknown): TelemetryBootstrap | null {
	if (!payload || typeof payload !== "object" || Array.isArray(payload)) return null;
	const record = payload as Record<string, unknown>;
	if (typeof record.distinctId !== "string" || record.distinctId.trim() === "") return null;
	if (typeof record.appVersion !== "string") return null;
	if (typeof record.platform !== "string") return null;
	if (!Array.isArray(record.disabledEvents)) return null;
	return {
		distinctId: record.distinctId,
		appVersion: record.appVersion,
		platform: record.platform as TelemetryBootstrap["platform"],
		disabledEvents: record.disabledEvents.filter((name): name is string => typeof name === "string"),
	};
}

async function fetchTelemetryBootstrap(): Promise<TelemetryBootstrap | null> {
	const baseUrl = await waitForTrustedApiBaseUrl(BOOTSTRAP_BASE_URL_TIMEOUT_MS);
	if (!baseUrl) return null;
	try {
		const response = await fetch(new URL("/internal/desktop/telemetry-bootstrap", baseUrl));
		if (!response.ok) return null;
		return parseTelemetryBootstrap(await response.json());
	} catch {
		return null;
	}
}

async function fetchSettings(): Promise<SettingsPayload> {
	const { data, error } = await apiClient.GET("/api/v1/settings");
	if (error) throw new Error(apiErrorMessage(error));
	if (!data) throw new Error("Settings response was empty");
	return data;
}

/** Records the durable preview-opened acknowledgement on the loopback daemon. */
export async function postPreviewOpenedAck(input: ExternalPreviewOpenInput): Promise<void> {
	if (!hasTrustedApiBaseUrl()) return;
	try {
		await fetch(new URL(`/internal/desktop/sessions/${encodeURIComponent(input.sessionId)}/preview-opened`, getApiBaseUrl()), {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({ revision: input.revision }),
		});
	} catch (error) {
		console.warn("Unable to record the preview-opened acknowledgement", error);
	}
}

export interface TauriBridgeTransports {
	invoke: (command: string, payload?: unknown) => Promise<unknown>;
	listen: (
		event: string,
		handler: (event: { payload: unknown }) => void,
	) => void | Promise<void> | (() => void) | Promise<() => void>;
}

export function createTauriBridge({ invoke, listen }: TauriBridgeTransports): OperatorBridge {
	const invokeDaemon = async (command: string): Promise<DaemonStatus> =>
		(await invoke(command)) as DaemonStatus;

	const subscribe = <T>(
		event: string,
		listener: (payload: T) => void,
	): (() => void) => {
		let disposed = false;
		let unlisten: (() => void) | null = null;
		const registered = listen(event, (event) => {
			if (!disposed) listener(event.payload as T);
		}) as Promise<() => void> | (() => void);
		if (registered && typeof (registered as Promise<() => void>).then === "function") {
			void (registered as Promise<() => void>)
				.then((dispose) => {
					if (typeof dispose !== "function") return;
					if (disposed) dispose();
					else unlisten = dispose;
				})
				.catch(() => undefined);
		} else if (typeof registered === "function") {
			unlisten = registered;
		}
		return () => {
			if (disposed) return;
			disposed = true;
			unlisten?.();
		};
	};

	return {
		app: {
			getVersion: async () => (await invoke("plugin:app|version")) as string,
			chooseDirectory: async (title?: string) =>
				(await invoke("choose_directory", { title })) as string | null,
			openExternal: async (url: string) => {
				await invoke("open_external", { url });
			},
			scanImportFolder: async (input: { path: string; mode: "project" | "workspace" }) => {
				const { data, error } = await apiClient.POST("/api/v1/dev/import-scan", { body: input });
				if (error) throw new Error(apiErrorMessage(error));
				return {
					path: data?.path ?? input.path,
					repos: (data?.repos ?? []).map((repo) => ({
						name: repo.name,
						path: repo.path,
						relativePath: repo.relativePath,
						branch: repo.branch,
						remote: repo.remote,
						hasRemote: repo.hasRemote,
						status: repo.status,
						...(repo.reason ? { reason: repo.reason } : {}),
					})),
					...(data?.setupWarning ? { setupWarning: data.setupWarning } : {}),
				} satisfies ImportFolderScan;
			},
			checkAncestorRepo: async (path: string) => {
				const { data, error } = await apiClient.POST("/api/v1/dev/ancestor-repository", { body: { path } });
				if (error) throw new Error(apiErrorMessage(error));
				return data?.setupWarning || undefined;
			},
			onNewSessionShortcut: (listener: () => void) => subscribe("shortcut:new-session", listener),
			onKeyboardShortcutsHelp: (listener: () => void) => subscribe("shortcut:help", listener),
			onNewShellTerminalShortcut: (listener: () => void) => subscribe("shortcut:new-shell-terminal", listener),
			onCloseShellTerminalShortcut: (listener: () => void) => subscribe("shortcut:close-shell-terminal", listener),
			setCloseShellTerminalShortcutEnabled: async (enabled: boolean) => {
				await invoke("set_close_shell_terminal_shortcut_enabled", { enabled });
			},
			onOpenSettingsShortcut: (listener: () => void) => subscribe("shortcut:open-settings", listener),
			onPreviousSessionShortcut: (listener: () => void) => subscribe("shortcut:previous-session", listener),
			onNextSessionShortcut: (listener: () => void) => subscribe("shortcut:next-session", listener),
			onPreviousTabShortcut: (listener: () => void) => subscribe("shortcut:previous-tab", listener),
			onNextTabShortcut: (listener: () => void) => subscribe("shortcut:next-tab", listener),
			onFocusTerminalShortcut: (listener: () => void) => subscribe("shortcut:focus-terminal", listener),
		},
		terminal: {
			saveDroppedFile: async (input: { name: string; bytes: Uint8Array }) =>
				(await invoke("stage_dropped_file", { name: input.name, data: encodeBase64(input.bytes) })) as string,
		},
		window: {
			setOverlay: async (overlay: { color: string; symbolColor: string }) => {
				await invoke("window_set_overlay", overlay);
			},
			isFullScreen: async () => (await invoke("window_is_fullscreen")) as boolean,
			onFullScreen: (listener: (fullScreen: boolean) => void) =>
				subscribe<boolean>("window:fullscreen", listener),
		},
		theme: {
			set: async (preference: "light" | "dark" | "system") => {
				await invoke("theme_set", { preference });
			},
		},
		menu: {
			action: async (action: string) => {
				await invoke("menu_action", { action });
			},
			notifyShellFocus: async () => {
				await invoke("shell_focus");
			},
		},
		clipboard: {
			writeText: async (text: string) => {
				await invoke("clipboard_write", { text });
			},
			readText: async () => (await invoke("clipboard_read")) as string,
		},
		daemon: {
			getStatus: () => invokeDaemon("daemon_status"),
			start: () => invokeDaemon("daemon_start"),
			stop: () => invokeDaemon("daemon_stop"),
			restart: () => invokeDaemon("daemon_restart"),
			onStatus: (listener: (status: DaemonStatus) => void) =>
				subscribe<DaemonStatus>("daemon:status", listener),
		},
		telemetry: {
			getBootstrap: () => fetchTelemetryBootstrap(),
		},
		preview: {
			openExternalPreview: async ({ url, sessionId, revision }: ExternalPreviewOpenInput) => {
				if (!isAllowedPreviewUrl(url)) throw new Error(`Preview target must be an HTTP(S) URL: ${url}`);
				await invoke("open_external", { url });
				await postPreviewOpenedAck({ sessionId, url, revision });
			},
		},
		notifications: {
			show: async (notification: { id: string; title: string; body?: string; type?: string }) => {
				await invoke("notification_show", notification);
			},
			setBadge: async (count: number) => {
				await invoke("notification_badge", { count });
			},
			devBounce: async () => {
				await invoke("notification_dev_bounce");
			},
			onClick: (listener: (id: string) => void) => subscribe<string>("notifications:click", listener),
		},
		tray: {
			setAttentionState: (state: TrayAttentionState) => {
				void invoke("tray_attention_state", state);
			},
			onOpenSession: (listener: (target: TrayOpenSessionTarget) => void) => {
				void Promise.resolve(invoke("tray_renderer_ready")).catch(() => undefined);
				return subscribe<TrayOpenSessionTarget>("tray:open-session", listener);
			},
		},
		appState: {
			getMigration: async () => (await fetchSettings()).migration ?? PENDING_MIGRATION,
			setMigration: async (migration: MigrationState) => {
				const { error } = await apiClient.PATCH("/api/v1/settings/migration", { body: migration });
				if (error) throw new Error(apiErrorMessage(error));
			},
		},
		updateSettings: {
			get: async () => {
				const updates = (await fetchSettings()).updates;
				const settings: UpdateSettings = updates
					? {
							enabled: updates.enabled,
							channel: updates.channel,
							nightlyAck: updates.nightlyAck,
							feature: updates.feature ?? null,
						}
					: DEFAULT_UPDATE_SETTINGS;
				void Promise.resolve(invoke("updates_apply_settings", { settings })).catch(() => undefined);
				return settings;
			},
			set: async (settings: UpdateSettings) => {
				const { error } = await apiClient.PATCH("/api/v1/settings/updates", {
					body: {
						enabled: settings.enabled,
						channel: settings.channel,
						nightlyAck: settings.nightlyAck,
						...(settings.feature ? { feature: { pr: settings.feature.pr } } : {}),
					},
				});
				if (error) throw new Error(apiErrorMessage(error));
				void Promise.resolve(invoke("updates_apply_settings", { settings })).catch(() => undefined);
			},
		},
		uiSettings: {
			get: async () => {
				const locale = coerceLocale((await fetchSettings()).ui?.locale);
				applyTrayLocale(invoke, locale);
				return { locale };
			},
			set: async (settings: UiSettings) => {
				const { data, error } = await apiClient.PATCH("/api/v1/settings/ui", {
					body: { locale: settings.locale },
				});
				if (error) throw new Error(apiErrorMessage(error));
				const locale = coerceLocale(data?.ui?.locale ?? settings.locale);
				applyTrayLocale(invoke, locale);
				return { locale };
			},
		},
		keybindings: {
			get: async () => {
				const keybindings = (await fetchSettings()).keybindings ?? {};
				void Promise.resolve(invoke("keybindings_apply", { overrides: keybindings })).catch(
					() => undefined,
				);
				return keybindings;
			},
			set: async (overrides: KeybindingOverrides) => {
				const body = Object.fromEntries(
					Object.entries(overrides).map(([id, bindings]) => [id, bindings.map((binding) => ({ ...binding }))]),
				);
				const { data, error } = await apiClient.PATCH("/api/v1/settings/keybindings", {
					body,
				});
				if (error) throw new Error(apiErrorMessage(error));
				const saved = data?.keybindings ?? {};
				void Promise.resolve(invoke("keybindings_apply", { overrides: saved })).catch(
					() => undefined,
				);
				return saved;
			},
			setRecording: async (active: boolean) => {
				await invoke("keybindings_recording", { active });
			},
		},
		updates: {
			getStatus: async () => (await invoke("updates_status")) as UpdateStatus,
			check: async (options?: { settings?: UpdateSettings; requestId?: string }) => {
				await invoke("updates_check", options);
			},
			returnHome: async (requestId?: string) => {
				await invoke("updates_return_home", { requestId });
			},
			download: async (requestId?: string) => {
				await invoke("updates_download", { requestId });
			},
			install: async () => {
				await invoke("updates_install");
			},
			onStatus: (listener: (status: UpdateStatus) => void) =>
				subscribe<UpdateStatus>("updates:status", listener),
			onTelemetry: (listener: (outcome: UpdateOutcome) => void) =>
				subscribe<UpdateOutcome>("updates:telemetry", listener),
		},
		featureBuilds: {
			list: async () => (await invoke("feature_builds_list")) as FeatureBuild[],
			getActive: async () => (await invoke("feature_builds_active")) as { pr: number } | null,
		},
	};
}

export type TauriBridge = ReturnType<typeof createTauriBridge>;
