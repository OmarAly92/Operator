import { create } from "zustand";
import type { TerminalTarget } from "../types/terminal";
import {
	applyDocumentSkin,
	readStoredThemePreference,
	readStoredThemeStyle,
	resolveTheme,
	runThemeTransition,
	systemTheme,
	themeStorageKey,
	themeStyleStorageKey,
	type Theme,
	type ThemePreference,
	type ThemeStyle,
} from "../lib/theme";
import {
	applyTerminalBackground,
	readStoredTerminalBackground,
	terminalBackgroundStorageKey,
	type TerminalBackground,
} from "../lib/terminal-background";

export type { Theme, ThemePreference, ThemeStyle } from "../lib/theme";
export type { TerminalBackground } from "../lib/terminal-background";
import { readStoredTerminalFontSize, terminalFontSizeStorageKey, type TerminalFontSize } from "../lib/terminal-font-size";
import {
	readStoredTerminalSecretRedaction,
	terminalSecretRedactionStorageKey,
} from "../lib/terminal-secret-redaction";
export { readStoredTerminalBackground } from "../lib/terminal-background";
export { readStoredThemePreference, readStoredThemeStyle, resolveTheme } from "../lib/theme";

export type SettingsModal =
	| { scope: "global"; section?: "general" | "claudeAccounts" | "mobile" | "updates" | "help" }
	| {
			scope: "project";
			projectId: string;
	  };

/** Worker detail view toggles — Changes (Git rail) is the default. */
export type WorkbenchTab = "changes" | "files" | "terminal";
export type InspectorView = "summary" | "files";

export type InspectorSessionState = {
	isOpen: boolean;
	view: InspectorView;
};

// Selection (which project/session is open) now lives in the URL — the router
// is the single source of truth, read via route params. This store holds only
// ephemeral UI: theme, sidebar collapse, command palette, per-session inspector
// state, and the active workbench tab within a session.
type UiState = {
	workbenchTab: WorkbenchTab;
	isSidebarOpen: boolean;
	inspectorSessions: Record<string, InspectorSessionState>;
	isCommandPaletteOpen: boolean;
	settingsModal: SettingsModal | null;
	themePreference: ThemePreference;
	/** Resolved light/dark for React consumers; may track OS while preference is system. */
	resolvedTheme: Theme;
	/** Named color style theme (e.g. "catppuccin", "nord") — independent of light/dark mode. */
	themeStyle: ThemeStyle;
	terminalBackground: TerminalBackground;
	terminalFontSize: TerminalFontSize;
	/** Mask daemon-shaped secrets in the terminal. Off by default. */
	terminalSecretRedaction: boolean;
	// Transient "open the New Task dialog for this project" signal. The nonce
	// bumps on every request so a repeat press (even for the same project) still
	// re-fires; the always-mounted GlobalNewTaskDialog consumes it. Selection
	// still lives in the URL — this is a one-shot action, not persisted state.
	newTaskRequest: { projectId: string; nonce: number } | null;
	// Bumps to ask the sidebar's create-project flow to open (the ⌘N fallback
	// when no project is in scope).
	createProjectNonce: number;
	// Bumps to ask for a new standalone shell terminal. Like newTaskRequest this
	// is a one-shot signal, not state: the tab-strip + button and Ctrl+Shift+` both
	// raise it so they cannot drift apart, and a repeat press re-fires because
	// the nonce always changes. The shell layout is its single consumer — it is
	// mounted on every route, so the request is honoured from anywhere in the app.
	newShellTerminalNonce: number;
	// The shell terminal the user most recently opened or selected. Both the
	// session view (tabs beside the session's pane) and the standalone terminals
	// view read it, so whichever one is on screen shows the same shell.
	activeShellTerminalHandleId: string | null;
	// Which terminal each mounted session is actually showing. The session pane
	// renders one terminal at a time, so opening a shell or the reviewer swaps
	// the agent's terminal off screen even though the route still points at that
	// session. Surfaces outside the session subtree (the notification runtime)
	// need that distinction, and SessionView's own target is local state.
	visibleTerminalKindBySession: Record<string, TerminalTarget["kind"]>;
	// Session tabs open in each project's session view, in strip order. Closing a
	// tab only takes the session off screen; the agent keeps running.
	openSessionTabsByProject: Record<string, string[]>;
	setWorkbenchTab: (tab: WorkbenchTab) => void;
	setThemePreference: (theme: ThemePreference) => void;
	setThemeStyle: (style: ThemeStyle) => void;
	setTerminalBackground: (background: TerminalBackground) => void;
	setTerminalFontSize: (size: TerminalFontSize) => void;
	setTerminalSecretRedaction: (enabled: boolean) => void;
	openGlobalSettings: () => void;
	openMobileSettings: () => void;
	openProjectSettings: (projectId: string) => void;
	closeSettings: () => void;
	/** Refresh resolvedTheme from OS without writing light/dark to storage. */
	syncSystemTheme: () => void;
	toggleSidebar: () => void;
	setInspectorOpen: (sessionId: string, isOpen: boolean) => void;
	toggleInspector: (sessionId: string) => void;
	setInspectorView: (sessionId: string, view: InspectorView) => void;
	setCommandPaletteOpen: (open: boolean) => void;
	requestNewTask: (projectId: string) => void;
	requestCreateProject: () => void;
	requestNewShellTerminal: () => void;
	setActiveShellTerminal: (handleId: string | null) => void;
	setVisibleTerminalKind: (sessionId: string, kind: TerminalTarget["kind"]) => void;
	clearVisibleTerminalKind: (sessionId: string) => void;
	openSessionTab: (projectId: string, sessionId: string, afterSessionId?: string) => void;
	closeSessionTab: (projectId: string, sessionId: string) => void;
};

const sidebarStorageKey = "opr.sidebar.open";
function getLocalStorage() {
	if (typeof window === "undefined" || !window.localStorage) return null;
	return window.localStorage;
}

function initialSidebarOpen() {
	return getLocalStorage()?.getItem(sidebarStorageKey) !== "false";
}

const inspectorStorageKey = "opr.inspector.open";

// Closed until asked for: the terminal is what a session is for, and the rail
// covers a third of it. toggleInspector writes this key, so the last explicit
// choice -- either way -- is what every session opened afterwards inherits.
function initialInspectorOpen() {
	return getLocalStorage()?.getItem(inspectorStorageKey) === "true";
}

let defaultInspectorOpen = initialInspectorOpen();

export function inspectorState(
	sessions: Record<string, InspectorSessionState>,
	sessionId: string,
): InspectorSessionState {
	return sessions[sessionId] ?? { isOpen: defaultInspectorOpen, view: "summary" };
}

const initialThemePreference = readStoredThemePreference();
const initialThemeStyle = readStoredThemeStyle();
const initialTerminalBackground = readStoredTerminalBackground();
const initialTerminalFontSize = readStoredTerminalFontSize();
const initialTerminalSecretRedaction = readStoredTerminalSecretRedaction();

export const useUiStore = create<UiState>((set, get) => ({
	workbenchTab: "changes",
	isSidebarOpen: initialSidebarOpen(),
	inspectorSessions: {},
	isCommandPaletteOpen: false,
	settingsModal: null,
	themePreference: initialThemePreference,
	resolvedTheme: resolveTheme(initialThemePreference),
	themeStyle: initialThemeStyle,
	terminalBackground: initialTerminalBackground,
	terminalFontSize: initialTerminalFontSize,
	terminalSecretRedaction: initialTerminalSecretRedaction,
	newTaskRequest: null,
	createProjectNonce: 0,
	newShellTerminalNonce: 0,
	activeShellTerminalHandleId: null,
	visibleTerminalKindBySession: {},
	openSessionTabsByProject: {},
	setWorkbenchTab: (workbenchTab) => set({ workbenchTab }),
	setThemePreference: (themePreference) => {
		if (get().themePreference === themePreference) return;
		runThemeTransition(() => {
			const resolvedTheme = resolveTheme(themePreference);
			getLocalStorage()?.setItem(themeStorageKey, themePreference);
			applyDocumentSkin(get().themeStyle, resolvedTheme);
			set({ themePreference, resolvedTheme });
		});
	},
	setThemeStyle: (themeStyle) => {
		if (get().themeStyle === themeStyle) return;
		runThemeTransition(() => {
			getLocalStorage()?.setItem(themeStyleStorageKey, themeStyle);
			applyDocumentSkin(themeStyle, get().resolvedTheme);
			set({ themeStyle });
		});
	},
	setTerminalBackground: (terminalBackground) => {
		if (get().terminalBackground === terminalBackground) return;
		getLocalStorage()?.setItem(terminalBackgroundStorageKey, terminalBackground);
		applyTerminalBackground(terminalBackground);
		set({ terminalBackground });
	},
	setTerminalFontSize: (terminalFontSize) => {
		if (get().terminalFontSize === terminalFontSize) return;
		getLocalStorage()?.setItem(terminalFontSizeStorageKey, String(terminalFontSize));
		set({ terminalFontSize });
	},
	setTerminalSecretRedaction: (terminalSecretRedaction) => {
		if (get().terminalSecretRedaction === terminalSecretRedaction) return;
		getLocalStorage()?.setItem(terminalSecretRedactionStorageKey, terminalSecretRedaction ? "1" : "0");
		set({ terminalSecretRedaction });
	},
	openGlobalSettings: () => set({ settingsModal: { scope: "global" } }),
	openMobileSettings: () => set({ settingsModal: { scope: "global", section: "mobile" } }),
	openProjectSettings: (projectId) => set({ settingsModal: { scope: "project", projectId } }),
	closeSettings: () => set({ settingsModal: null }),
	syncSystemTheme: () => {
		const { themePreference, resolvedTheme } = get();
		if (themePreference !== "system") return;
		const next = systemTheme();
		if (next === resolvedTheme) return;
		runThemeTransition(() => {
			applyDocumentSkin(get().themeStyle, next);
			set({ resolvedTheme: next });
		});
	},
	toggleSidebar: () =>
		set((state) => {
			const isSidebarOpen = !state.isSidebarOpen;
			getLocalStorage()?.setItem(sidebarStorageKey, String(isSidebarOpen));
			return { isSidebarOpen };
		}),
	setInspectorOpen: (sessionId, isOpen) =>
		set((state) => {
			const current = inspectorState(state.inspectorSessions, sessionId);
			return {
				inspectorSessions: {
					...state.inspectorSessions,
					[sessionId]: { ...current, isOpen },
				},
			};
		}),
	toggleInspector: (sessionId) =>
		set((state) => {
			const current = inspectorState(state.inspectorSessions, sessionId);
			const isOpen = !current.isOpen;
			defaultInspectorOpen = isOpen;
			getLocalStorage()?.setItem(inspectorStorageKey, String(isOpen));
			return {
				inspectorSessions: {
					...state.inspectorSessions,
					[sessionId]: { ...current, isOpen },
				},
			};
		}),
	setInspectorView: (sessionId, view) =>
		set((state) => {
			const current = inspectorState(state.inspectorSessions, sessionId);
			if (current.view === view) return state;
			return {
				inspectorSessions: {
					...state.inspectorSessions,
					[sessionId]: { ...current, view },
				},
			};
		}),
	setCommandPaletteOpen: (isCommandPaletteOpen) => set({ isCommandPaletteOpen }),
	requestNewTask: (projectId) =>
		set((state) => ({ newTaskRequest: { projectId, nonce: (state.newTaskRequest?.nonce ?? 0) + 1 } })),
	requestCreateProject: () => set((state) => ({ createProjectNonce: state.createProjectNonce + 1 })),
	requestNewShellTerminal: () => set((state) => ({ newShellTerminalNonce: state.newShellTerminalNonce + 1 })),
	setActiveShellTerminal: (activeShellTerminalHandleId) => set({ activeShellTerminalHandleId }),
	setVisibleTerminalKind: (sessionId, kind) =>
		set((state) =>
			state.visibleTerminalKindBySession[sessionId] === kind
				? state
				: { visibleTerminalKindBySession: { ...state.visibleTerminalKindBySession, [sessionId]: kind } },
		),
	clearVisibleTerminalKind: (sessionId) =>
		set((state) => {
			if (!(sessionId in state.visibleTerminalKindBySession)) return state;
			const visibleTerminalKindBySession = { ...state.visibleTerminalKindBySession };
			delete visibleTerminalKindBySession[sessionId];
			return { visibleTerminalKindBySession };
		}),
	openSessionTab: (projectId, sessionId, afterSessionId) =>
		set((state) => {
			const tabs = state.openSessionTabsByProject[projectId] ?? [];
			if (tabs.includes(sessionId)) return state;
			const anchor = afterSessionId ? tabs.indexOf(afterSessionId) : -1;
			const next = anchor < 0 ? [...tabs, sessionId] : [...tabs.slice(0, anchor + 1), sessionId, ...tabs.slice(anchor + 1)];
			return { openSessionTabsByProject: { ...state.openSessionTabsByProject, [projectId]: next } };
		}),
	closeSessionTab: (projectId, sessionId) =>
		set((state) => {
			const tabs = state.openSessionTabsByProject[projectId];
			if (!tabs?.includes(sessionId)) return state;
			return {
				openSessionTabsByProject: {
					...state.openSessionTabsByProject,
					[projectId]: tabs.filter((id) => id !== sessionId),
				},
			};
		}),
}));

export function useResolvedTheme(): Theme {
	return useUiStore((state) => state.resolvedTheme);
}
