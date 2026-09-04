import { useQuery } from "@tanstack/react-query";
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { useTranslation } from "react-i18next";
import type { PanelImperativeHandle, PanelSize } from "react-resizable-panels";
import type { components } from "../../api/schema";
import { CenterPane, SessionBlocksPane } from "./CenterPane";
import { SessionFilesView } from "./SessionFilesView";
import { SessionInspector } from "./SessionInspector";
import { ShellTopbar } from "./ShellTopbar";
import { ResizableHandle, ResizablePanel, ResizablePanelGroup } from "./ui/resizable";
import { useExternalPreview } from "../hooks/useExternalPreview";
import { useWorkspaceQuery } from "../hooks/useWorkspaceQuery";
import { useWindowFullScreen } from "../hooks/useWindowFullScreen";
import { apiClient, apiErrorMessage } from "../lib/api-client";
import { nativeShellBridgePresent } from "../lib/bridge";
import { hidesShellTopbar } from "../lib/platform";
import { useShell } from "../lib/shell-context";
import { cn } from "../lib/utils";
import { isOrchestratorSession, sessionIsActive } from "../types/workspace";
import { terminalTargetBelongsToSession, type TerminalTarget } from "../types/terminal";
import { matchesRendererShortcut } from "../stores/keybindings-store";
import { useResolvedTheme, useUiStore, type InspectorView } from "../stores/ui-store";

const INSPECTOR_MIN_PERCENT = 30;
const INSPECTOR_MAX_PERCENT = 45;
const inspectorSplitStorageKey = "opr.inspector.split";
const shellTopbarHiddenByPlatform = hidesShellTopbar();

type ReviewsResponse = components["schemas"]["ListReviewsResponse"];
type ReviewerTerminalTarget = { handleId: string; harness: string };

function initialSplitPercent(): number {
	const raw = typeof window === "undefined" ? null : window.localStorage?.getItem(inspectorSplitStorageKey);
	const parsed = raw === null ? Number.NaN : Number(raw);
	if (!Number.isFinite(parsed)) return INSPECTOR_MIN_PERCENT;
	return Math.min(INSPECTOR_MAX_PERCENT, Math.max(INSPECTOR_MIN_PERCENT, parsed));
}

function reviewerTerminalFromReviews(data?: ReviewsResponse): ReviewerTerminalTarget | undefined {
	const handleId = data?.reviewerHandleId?.trim();
	if (!handleId) return undefined;
	const latest = data?.reviews?.find((review) => review.latestRun)?.latestRun;
	return { handleId, harness: data?.reviewerHarness || latest?.harness || "codex" };
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
	const theme = useResolvedTheme();
	const isInspectorOpen = useUiStore((state) => state.inspectorSessions[sessionId]?.isOpen ?? true);
	const inspectorView = useUiStore((state) => state.inspectorSessions[sessionId]?.view ?? "summary");
	const setInspectorOpenForSession = useUiStore((state) => state.setInspectorOpen);
	const toggleInspector = useUiStore((state) => state.toggleInspector);
	const setInspectorViewForSession = useUiStore((state) => state.setInspectorView);
	const { daemonStatus } = useShell();
	const inspectorRef = useRef<PanelImperativeHandle | null>(null);
	const inspectorSeparatorRef = useRef<HTMLDivElement | null>(null);
	const [terminalTarget, setTerminalTarget] = useState<TerminalTarget>({ kind: "worker" });
	const [filesPoppedOut, setFilesPoppedOut] = useState(false);
	const isNativeFullScreen = useWindowFullScreen();

	const session = workspaces.flatMap((workspace) => workspace.sessions).find((s) => s.id === sessionId);
	const reviewerQuery = useQuery({
		queryKey: ["session-reviews", sessionId],
		enabled: Boolean(
			nativeShellBridgePresent() && session && sessionIsActive(session) && !isOrchestratorSession(session) && session.prs.length > 0,
		),
		refetchInterval: (query) => {
			const data = query.state.data as ReviewsResponse | undefined;
			return data?.reviews?.some((review) => review.status === "running") ? 2500 : false;
		},
		queryFn: async () => {
			const { data, error } = await apiClient.GET("/api/v1/sessions/{sessionId}/reviews", {
				params: { path: { sessionId } },
			});
			if (error) throw new Error(apiErrorMessage(error, "Unable to load reviews"));
			return data ?? ({ reviewerHandleId: "", reviews: [], runs: [] } satisfies ReviewsResponse);
		},
	});
	const availableReviewerTerminal = reviewerTerminalFromReviews(reviewerQuery.data);
	const reviewerTerminal = session && sessionIsActive(session) ? availableReviewerTerminal : undefined;

	const setVisibleTerminalKind = useUiStore((state) => state.setVisibleTerminalKind);
	const clearVisibleTerminalKind = useUiStore((state) => state.clearVisibleTerminalKind);

	const selectSessionTerminal = useCallback(() => {
		setTerminalTarget({ kind: "worker" });
	}, []);
	const selectReviewerTerminal = useCallback((target: ReviewerTerminalTarget) => {
		setTerminalTarget({ kind: "reviewer", handleId: target.handleId, harness: target.harness, sessionId });
	}, [sessionId]);

	useEffect(() => {
		setTerminalTarget((current) =>
			current.kind === "reviewer" &&
			(!availableReviewerTerminal || availableReviewerTerminal.handleId !== current.handleId)
				? { kind: "worker" }
				: current,
		);
	}, [availableReviewerTerminal]);
	const isOrchestrator = session ? isOrchestratorSession(session) : false;
	// Orchestrators get the full workspace width; only workers need the inspector rail.
	const hasInspector = Boolean(session && !isOrchestrator);
	const sessionHeaderActions = <ShellTopbar embedded />;
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
		setTerminalTarget({ kind: "worker" });
		setFilesPoppedOut(false);
	}, [sessionId]);

	// Route props change one render before the passive reset above. Reject the
	// previous session's shell/reviewer synchronously so its handle can never be
	// cached under the destination session.
	const routedTerminalTarget = terminalTargetBelongsToSession(terminalTarget, sessionId)
		? terminalTarget
		: ({ kind: "worker" } satisfies TerminalTarget);
	const showChatSurface = session?.mode === "chat" && routedTerminalTarget.kind === "worker";

	// The pane shows one terminal at a time, so selecting a shell or the reviewer
	// takes the agent's terminal off screen while the route still points here.
	// Publish which one is showing: the notification runtime lives outside this
	// subtree and must not treat "on the session route" as "watching the agent".
	useEffect(() => {
		setVisibleTerminalKind(sessionId, routedTerminalTarget.kind);
		return () => clearVisibleTerminalKind(sessionId);
	}, [clearVisibleTerminalKind, routedTerminalTarget.kind, sessionId, setVisibleTerminalKind]);

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
			const currentOpen = useUiStore.getState().inspectorSessions[sessionId]?.isOpen ?? true;
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
					<div className="relative h-full min-h-0">
						{/* The committed mode owns the agent surface. Auxiliary shell and
						    reviewer targets remain terminal surfaces in either mode. */}
						{showChatSurface ? (
							<SessionBlocksPane session={session} headerActions={sessionHeaderActions} />
						) : (
							<CenterPane
								daemonReady={daemonStatus.state === "ready"}
								onSelectSessionTerminal={selectSessionTerminal}
								onSelectReviewerTerminal={selectReviewerTerminal}
								reviewerTerminal={reviewerTerminal}
								session={session}
								terminalTarget={routedTerminalTarget}
								theme={theme}
								topbarActions={sessionHeaderActions}
							/>
						)}
					</div>
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
									onOpenReviewerTerminal={selectReviewerTerminal}
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
