import type { KeybindingOverrides } from "./shortcuts";
import type { TrayAttentionState, TrayOpenSessionTarget } from "./tray";
import type { DaemonStatus } from "./daemon-status";
import type { TelemetryBootstrap } from "./telemetry";
import type { MigrationState } from "./app-state";
import type { UpdateSettings, UpdateStatus } from "./update-settings";
import type { UpdateOutcome } from "./update-telemetry";
import type { UiSettings } from "./ui-locale";
import type { FeatureBuild } from "./feature-builds";
import type { ImportFolderMode, ImportFolderScan } from "./import-folder-scan";

/** One automatic external-preview open the shell should acknowledge durably. */
export type ExternalPreviewOpenInput = {
	sessionId: string;
	url: string;
	revision: number;
};

export type { ImportFolderMode, ImportFolderScan } from "./import-folder-scan";

export interface UpdateCheckOptions {
	settings?: UpdateSettings;
	requestId?: string;
}

export interface FeatureBuildRef {
	pr: number;
}

export type OperatorBridge = {
	app: {
		getVersion: () => Promise<string>;
		chooseDirectory: (title?: string) => Promise<string | null>;
		openExternal: (url: string) => Promise<void>;
		scanImportFolder: (input: { path: string; mode: ImportFolderMode }) => Promise<ImportFolderScan>;
		checkAncestorRepo: (path: string) => Promise<string | undefined>;
		onNewSessionShortcut: (listener: () => void) => () => void;
		onKeyboardShortcutsHelp: (listener: () => void) => () => void;
		onNewShellTerminalShortcut: (listener: () => void) => () => void;
		onCloseShellTerminalShortcut: (listener: () => void) => () => void;
		setCloseShellTerminalShortcutEnabled: (enabled: boolean) => void;
		onOpenSettingsShortcut: (listener: () => void) => () => void;
		onPreviousSessionShortcut: (listener: () => void) => () => void;
		onNextSessionShortcut: (listener: () => void) => () => void;
		onPreviousTabShortcut: (listener: () => void) => () => void;
		onNextTabShortcut: (listener: () => void) => () => void;
		onFocusTerminalShortcut: (listener: () => void) => () => void;
	};
	terminal: {
		saveDroppedFile: (input: { name: string; bytes: Uint8Array }) => Promise<string>;
	};
	window: {
		setOverlay: (overlay: { color: string; symbolColor: string }) => Promise<void>;
		isFullScreen: () => Promise<boolean>;
		onFullScreen: (listener: (fullScreen: boolean) => void) => () => void;
	};
	theme: {
		set: (preference: "light" | "dark" | "system") => Promise<void>;
	};
	menu: {
		action: (action: string) => Promise<void>;
		notifyShellFocus: () => void;
	};
	clipboard: {
		writeText: (text: string) => Promise<void>;
		readText: () => Promise<string>;
	};
	daemon: {
		getStatus: () => Promise<DaemonStatus>;
		start: () => Promise<DaemonStatus>;
		stop: () => Promise<DaemonStatus>;
		restart: () => Promise<DaemonStatus>;
		onStatus: (listener: (status: DaemonStatus) => void) => () => void;
	};
	telemetry: {
		getBootstrap: () => Promise<TelemetryBootstrap | null>;
	};
	preview: {
		openExternalPreview: (input: ExternalPreviewOpenInput) => Promise<void>;
	};
	notifications: {
		show: (notification: { id: string; title: string; body?: string; type?: string }) => Promise<void>;
		setBadge: (count: number) => Promise<void>;
		devBounce: () => Promise<void>;
		onClick: (listener: (id: string) => void) => () => void;
	};
	tray: {
		setAttentionState: (state: TrayAttentionState) => void;
		onOpenSession: (listener: (target: TrayOpenSessionTarget) => void) => () => void;
	};
	appState: {
		getMigration: () => Promise<MigrationState>;
		setMigration: (migration: MigrationState) => Promise<void>;
	};
	updateSettings: {
		get: () => Promise<UpdateSettings>;
		set: (settings: UpdateSettings) => Promise<void>;
	};
	uiSettings: {
		get: () => Promise<UiSettings>;
		set: (settings: UiSettings) => Promise<UiSettings>;
	};
	keybindings: {
		get: () => Promise<KeybindingOverrides>;
		set: (overrides: KeybindingOverrides) => Promise<KeybindingOverrides>;
		setRecording: (active: boolean) => Promise<void>;
	};
	updates: {
		getStatus: () => Promise<UpdateStatus>;
		check: (options?: UpdateCheckOptions) => Promise<void>;
		returnHome: (requestId?: string) => Promise<void>;
		download: (requestId?: string) => Promise<void>;
		install: () => Promise<void>;
		onStatus: (listener: (status: UpdateStatus) => void) => () => void;
		onTelemetry: (listener: (outcome: UpdateOutcome) => void) => () => void;
	};
	featureBuilds: {
		list: () => Promise<FeatureBuild[]>;
		getActive: () => Promise<FeatureBuildRef | null>;
	};
};
