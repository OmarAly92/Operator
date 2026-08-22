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
import type { OperatorBridgeWithoutBrowser } from "../../shared/operator-bridge";
import { apiClient, apiErrorMessage } from "./api-client";

type SettingsPayload = components["schemas"]["SettingsResponse"];

const PENDING_MIGRATION: MigrationState = { status: "pending" };
const DEFAULT_UPDATE_SETTINGS: UpdateSettings = {
	enabled: false,
	channel: "latest",
	nightlyAck: false,
	feature: null,
};

async function fetchSettings(): Promise<SettingsPayload | null> {
	const { data } = await apiClient.GET("/api/v1/settings");
	return data ?? null;
}

export interface TauriBridgeTransports {
	invoke: (command: string, payload?: unknown) => Promise<unknown>;
	listen: (
		event: string,
		handler: (event: { payload: unknown }) => void,
	) => void | Promise<void> | (() => void) | Promise<() => void>;
}

export function createTauriBridge({ invoke, listen }: TauriBridgeTransports): OperatorBridgeWithoutBrowser {
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
			void (registered as Promise<() => void>).then((dispose) => {
				if (disposed) dispose();
				else unlisten = dispose;
			});
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
			getVersion: async () => (await invoke("app_version")) as string,
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
				(await invoke("stage_dropped_file", input)) as string,
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
			getBootstrap: async (): Promise<TelemetryBootstrap | null> => null,
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
			onOpenSession: (listener: (target: TrayOpenSessionTarget) => void) =>
				subscribe<TrayOpenSessionTarget>("tray:open-session", listener),
		},
		appState: {
			getMigration: async () => (await fetchSettings())?.migration ?? PENDING_MIGRATION,
			setMigration: async (migration: MigrationState) => {
				const { error } = await apiClient.PATCH("/api/v1/settings/migration", { body: migration });
				if (error) throw new Error(apiErrorMessage(error));
			},
		},
		updateSettings: {
			get: async () => {
				const updates = (await fetchSettings())?.updates;
				if (!updates) return DEFAULT_UPDATE_SETTINGS;
				return {
					enabled: updates.enabled,
					channel: updates.channel,
					nightlyAck: updates.nightlyAck,
					feature: updates.feature ?? null,
				};
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
			},
		},
		uiSettings: {
			get: async () => ({ locale: coerceLocale((await fetchSettings())?.ui?.locale) }),
			set: async (settings: UiSettings) => {
				const { data, error } = await apiClient.PATCH("/api/v1/settings/ui", {
					body: { locale: settings.locale },
				});
				if (error) throw new Error(apiErrorMessage(error));
				return { locale: coerceLocale(data?.ui?.locale ?? settings.locale) };
			},
		},
		keybindings: {
			get: async () => (await fetchSettings())?.keybindings ?? {},
			set: async (overrides: KeybindingOverrides) => {
				const body = Object.fromEntries(
					Object.entries(overrides).map(([id, bindings]) => [id, bindings.map((binding) => ({ ...binding }))]),
				);
				const { data, error } = await apiClient.PATCH("/api/v1/settings/keybindings", {
					body,
				});
				if (error) throw new Error(apiErrorMessage(error));
				return data?.keybindings ?? {};
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
