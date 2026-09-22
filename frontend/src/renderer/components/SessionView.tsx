import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { useTranslation } from "react-i18next";
import type { PanelImperativeHandle, PanelSize } from "react-resizable-panels";
import { SessionFilesView } from "./SessionFilesView";
import { SessionInspector } from "./SessionInspector";
import { ResizableHandle, ResizablePanel, ResizablePanelGroup } from "./ui/resizable";
import { SplitWorkspace } from "./split/SplitWorkspace";
import { useExternalPreview } from "../hooks/useExternalPreview";
import { useWorkspaceQuery } from "../hooks/useWorkspaceQuery";
import { useWindowFullScreen } from "../hooks/useWindowFullScreen";
import { hidesShellTopbar } from "../lib/platform";
import { cn } from "../lib/utils";
import { sessionIsActive } from "../types/workspace";
import { matchesRendererShortcut } from "../stores/keybindings-store";
import { inspectorState, useUiStore, type InspectorView } from "../stores/ui-store";
import { useSplitLayoutStore } from "../stores/split-layout-store";

const INSPECTOR_MIN_PERCENT = 30;
const INSPECTOR_MAX_PERCENT = 45;
const inspectorSplitStorageKey = "opr.inspector.split";
const shellTopbarHiddenByPlatform = hidesShellTopbar();

function initialSplitPercent(): number {
	const raw = typeof window === "undefined" ? null : window.localStorage?.getItem(inspectorSplitStorageKey);
	const parsed = raw === null ? Number.NaN : Number(raw);
	if (!Number.isFinite(parsed)) return INSPECTOR_MIN_PERCENT;
	return Math.min(INSPECTOR_MAX_PERCENT, Math.max(INSPECTOR_MIN_PERCENT, parsed));
}

type SessionViewProps = {
	sessionId: string;
};

// The session detail screen: terminal + git rail. On Win/Linux the shell owns
// ShellTopbar above this view; when the platform hides the shell topbar
// (macOS), the same topbar mounts here so the outer panel stays full-height.
// Rendered by both the project-scoped and cross-project session routes.
// The persistent shell cache owns terminal lifetime by logical session + handle:
// route switches retain the xterm instance and latest output, while a replacement
// handle gets a clean xterm/mux binding.
//
// The split is shadcn's resizable (react-resizable-panels v4) with a fully
// collapsible inspector driven to 0% via the imperative API from the ui-store
// (topbar button / ⌘⇧B), animated by the flex-grow transition in styles.css.
// The panel is `collapsible` only while closed: rrp snaps a collapsible panel
// to 0% when a drag crosses minSize, so an always-collapsible inspector let a
// drag vanish the rail. While open the panel is non-collapsible and a drag
// hard-stops at INSPECTOR_MIN_PERCENT; only the explicit controls collapse it.
// Content keeps a stable min-width inside the clipped panel so nothing reflows
// mid-animation; split width persists.
export function SessionView({ sessionId }: SessionViewProps) {
	const { t } = useTranslation();
	const workspaceQuery = useWorkspaceQuery();
	const workspaces = workspaceQuery.data ?? [];
	const isInspectorOpen = useUiStore((state) => inspectorState(state.inspectorSessions, sessionId).isOpen);
	const inspectorView = useUiStore((state) => state.inspectorSessions[sessionId]?.view ?? "summary");
	const setInspectorOpenForSession = useUiStore((state) => state.setInspectorOpen);
	const toggleInspector = useUiStore((state) => state.toggleInspector);
	const setInspectorViewForSession = useUiStore((state) => state.setInspectorView);
	const inspectorRef = useRef<PanelImperativeHandle | null>(null);
	const inspectorSeparatorRef = useRef<HTMLDivElement | null>(null);
	const [filesPoppedOut, setFilesPoppedOut] = useState(false);
	const isNativeFullScreen = useWindowFullScreen();

	const session = workspaces.flatMap((workspace) => workspace.sessions).find((s) => s.id === sessionId);

	const hasInspector = Boolean(session);
	const previewUrl = session?.previewUrl?.trim() || undefined;
	const previewRevision = session?.previewRevision;
	const terminated = session ? !sessionIsActive(session) : false;
	const externalPreview = useExternalPreview({
		sessionId: session?.id,
		previewUrl,
		previewRevision,
		previewOpenedRevision: session?.previewOpenedRevision,
		terminated,
	});
	const handleReopenPreview = useCallback(() => {
		if (!previewUrl) return;
		void externalPreview.reopen(previewUrl);
	}, [externalPreview, previewUrl]);

	useLayoutEffect(() => {
		setFilesPoppedOut(false);
	}, [sessionId]);

	const handleOpenReviewerTerminal = useCallback(
		(target: { handleId: string; harness: string }) => {
			useSplitLayoutStore.getState().openTab({ kind: "reviewer", sessionId, handleId: target.handleId, harness: target.harness });
		},
		[sessionId],
	);

	const handleOpenFiles = useCallback(() => {
		setFilesPoppedOut(false);
		setInspectorViewForSession(sessionId, "files");
		setInspectorOpenForSession(sessionId, true);
	}, [sessionId, setInspectorOpenForSession, setInspectorViewForSession]);

	const handleToggleFilesPopOut = useCallback(
		(next: boolean) => {
			setFilesPoppedOut(next);
			setInspectorViewForSession(sessionId, "files");
			setInspectorOpenForSession(sessionId, true);
		},
		[sessionId, setInspectorOpenForSession, setInspectorViewForSession],
	);

	const inspectorDefaultSizeRef = useRef<string | null>(null);
	if (!hasInspector) {
		inspectorDefaultSizeRef.current = null;
	} else if (inspectorDefaultSizeRef.current === null) {
		inspectorDefaultSizeRef.current = isInspectorOpen ? `${initialSplitPercent()}%` : "0%";
	}
	const inspectorDefaultSize = inspectorDefaultSizeRef.current ?? "0%";

	useEffect(() => {
		if (!hasInspector) return;
		const handleKeyDown = (event: KeyboardEvent) => {
			if (!matchesRendererShortcut("toggle-inspector", event)) return;
			event.preventDefault();
			toggleInspector(sessionId);
		};
		window.addEventListener("keydown", handleKeyDown);
		return () => window.removeEventListener("keydown", handleKeyDown);
	}, [hasInspector, sessionId, toggleInspector]);

	// Drive the collapsible panel from the store so the topbar button, ⌘⇧B, and
	// drag-to-reopen all stay in sync. When the inspector panel mounts into
	// the already-live group (orchestrator/loading → worker), rrp only derives
	// the new panel's constraints in the next commit. This effect intentionally
	// runs before the readiness effect below, so mount and StrictMode's effect
	// replay remain imperative-free; later store changes can safely drive the
	// registered panel.
	const inspectorImperativeReadyRef = useRef(false);
	useEffect(() => {
		if (!hasInspector || !inspectorImperativeReadyRef.current) return;
		const panel = inspectorRef.current;
		if (!panel) return;
		if (isInspectorOpen) {
			// resize(), not expand(): by the time this effect runs the panel has
			// re-registered as non-collapsible (open panels refuse drag-collapse),
			// and rrp's expand() no-ops on a non-collapsible panel. resize() also
			// restores the persisted split regardless of what "most recent size"
			// rrp remembers, which is 0 when the panel mounted collapsed.
			panel.resize(`${initialSplitPercent()}%`);
			return;
		}
		// Closing flips `collapsible` back on in this same commit, but rrp only
		// re-derives the group's constraints in the follow-up commit its
		// registration effect schedules — so this first collapse() still sees the
		// open panel's non-collapsible constraints and no-ops. Repeat it on the
		// next frame, when the fresh constraints have landed; collapse() is
		// idempotent, so the double call is safe wherever the derivation lands.
		panel.collapse();
		const frame = window.requestAnimationFrame(() => panel.collapse());
		return () => window.cancelAnimationFrame(frame);
	}, [hasInspector, isInspectorOpen]);
	useEffect(() => {
		if (!hasInspector || !inspectorRef.current) {
			inspectorImperativeReadyRef.current = false;
			return;
		}
		inspectorImperativeReadyRef.current = true;
		return () => {
			inspectorImperativeReadyRef.current = false;
		};
	}, [hasInspector]);

	// Persist drags and mirror a drag-reopen (dragging the separator of a
	// collapsed inspector past the snap point) back into the store. Dragging an
	// open inspector can never collapse it — the panel is non-collapsible while
	// open, so rrp clamps the drag at minSize instead of snapping to 0%.
	// Read the store imperatively to avoid a stale closure.
	// Gated on an actively dragged separator: rrp v4 derives sizes from the
	// observed DOM layout, so the flex-grow transition that animates
	// resize()/collapse() (styles.css) fires onResize with transient
	// mid-animation sizes too. Writing those back turned the imperative
	// collapse into a feedback loop — a mid-collapse size read as "dragged
	// back open", re-toggled the store, and the panel bounced back (the
	// topbar button looked dead). rrp marks the separator
	// data-separator="active" only during a pointer drag — the same hook the
	// transition-suppressing CSS keys on, so drag writes are never transition
	// frames.
	// Also wrapped in useCallback: rrp v4's panel registration useLayoutEffect
	// includes onResize in its dep array, so an unstable reference would
	// de-register/re-register the inspector panel on every render and race
	// with the resize()/collapse() effect above.
	const handleInspectorResize = useCallback(
		(size: PanelSize) => {
			if (inspectorSeparatorRef.current?.getAttribute("data-separator") !== "active") return;
			if (size.asPercentage <= 0) return;
			window.localStorage?.setItem(inspectorSplitStorageKey, String(size.asPercentage));
			const currentOpen = inspectorState(useUiStore.getState().inspectorSessions, sessionId).isOpen;
			if (!currentOpen) toggleInspector(sessionId);
		},
		[sessionId, toggleInspector],
	);

	if (!session && !workspaceQuery.isLoading) {
		return (
			<div className="grid h-full place-items-center p-6 text-center font-mono text-xs text-passive">
				{t("session.notFound")}
			</div>
		);
	}

	return (
		<div className="relative flex h-full min-h-0 flex-col bg-background text-foreground" data-testid="session-detail">
			<ResizablePanelGroup className="session-split min-h-0 flex-1" id="session-workspace" orientation="horizontal">
				{/* react-resizable-panels v4: bare numbers are PIXELS; percentages must
            be strings. Numeric sizes here once clamped the inspector to 45px. */}
				{/* RRP's inner panel defaults to overflow:auto. Nothing scrolls at pane level,
				    so clip the chat rail's active marker instead of creating a horizontal scrollbar. */}
				<ResizablePanel defaultSize="72%" id="terminal" minSize="45%" style={{ overflow: "hidden" }}>
					<SplitWorkspace routeSessionId={sessionId} />
				</ResizablePanel>
				{hasInspector ? (
					<>
						<ResizableHandle
							className="w-1.75 cursor-col-resize touch-none bg-transparent after:w-px after:bg-border-strong hover:after:bg-border focus-visible:ring-0 focus-visible:ring-offset-0 focus-visible:after:bg-border data-[separator=active]:after:bg-border"
							elementRef={inspectorSeparatorRef}
						/>
						<ResizablePanel
							aria-hidden={!isInspectorOpen}
							collapsible={!isInspectorOpen}
							defaultSize={inspectorDefaultSize}
							id="inspector"
							inert={!isInspectorOpen}
							maxSize={`${INSPECTOR_MAX_PERCENT}%`}
							minSize={`${INSPECTOR_MIN_PERCENT}%`}
							onResize={handleInspectorResize}
							panelRef={inspectorRef}
							style={{ overflow: "hidden" }}
						>
							{/* Stable content width while the panel animates (yyork pattern):
                  the pane clips instead of reflowing the inspector mid-collapse. */}
							<div className="h-full min-w-inspector-min">
								<SessionInspector
									filesView={
										session ? (
											<SessionFilesView onToggleMaximized={handleToggleFilesPopOut} sessionId={session.id} />
										) : null
									}
									isInspectorVisible={isInspectorOpen}
									onOpenFiles={handleOpenFiles}
									onOpenReviewerTerminal={handleOpenReviewerTerminal}
									onReopenPreview={handleReopenPreview}
									onRetryPreview={externalPreview.retry}
									onViewChange={(next: InspectorView) => setInspectorViewForSession(sessionId, next)}
									previewError={externalPreview.error || undefined}
									previewUrl={previewUrl}
									view={inspectorView}
									session={session}
								/>
							</div>
						</ResizablePanel>
					</>
				) : null}
			</ResizablePanelGroup>
			{filesPoppedOut && session
				? createPortal(
						<div
							className={cn(
								"files-popout-overlay",
								shellTopbarHiddenByPlatform && !isNativeFullScreen && "files-popout-overlay--mac-windowed",
							)}
						>
							<SessionFilesView
								isMaximized
								onToggleMaximized={handleToggleFilesPopOut}
								sessionId={session.id}
							/>
						</div>,
						document.body,
					)
				: null}
</div>
	);
}
