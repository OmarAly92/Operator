import { useEffect, useRef, useState, type KeyboardEvent, type MouseEvent, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import type { TFunction } from "i18next";
import { useQueryClient } from "@tanstack/react-query";
import { useNavigate } from "@tanstack/react-router";
import {
	Check,
	Copy,
	FolderOpen,
	GitBranch,
	LoaderCircle,
	RotateCcw,
	SquareTerminal,
	Trash2,
} from "lucide-react";
import { type WorkspaceSession, canonicalTrackerIssueId } from "../types/workspace";
import {
	attentionZone,
	boardAttentionZoneOrder,
	getAgentActivityView,
	getAttentionZoneViewForZone,
	getSessionStatusView,
	isSessionIdle,
	type AttentionZone,
	type AttentionZoneView,
} from "../lib/session-presentation";
import { useSessionScmSummary, type SessionPRSummary } from "../hooks/useSessionScmSummary";
import {
	useSessionUsageSummaries,
	type SessionUsageSummary,
} from "../hooks/useSessionUsageSummaries";
import { useRestoreSession } from "../hooks/useRestoreSession";
import { useOpenShellTerminal } from "../hooks/useShellTerminals";
import {
	clearTerminateSessionState,
	useTerminateSession,
	useTerminateSessionState,
} from "../hooks/useTerminateSession";
import { useWorkspaceQuery, workspaceQueryKey } from "../hooks/useWorkspaceQuery";
import { BoardWelcome, ProjectBoardEmpty } from "./BoardEmptyStates";
import { AgentAvatar } from "./AgentAvatar";
import { prBrowserUrl, sessionPRDisplaySummaries } from "../lib/pr-display";
import { formatTimeCompact } from "../lib/format-time";
import { formatTokenCount } from "../lib/format-token-count";
import { SessionClaudeAccountChip } from "./SessionClaudeAccountChip";
import { operatorBridge } from "../lib/bridge";
import { usesPreviewWorkspaceData } from "../lib/preview-mode";
import { cn } from "../lib/utils";
import { shellChromeDragRegion } from "../lib/platform";
import { useUiStore } from "../stores/ui-store";
import { RestoreUnavailableDialog } from "./RestoreUnavailableDialog";
import { Tooltip, TooltipContent, TooltipTrigger } from "./ui/tooltip";
import { SessionTerminationPopover } from "./SessionTerminationPopover";
import { DaemonStartupLoader } from "./DaemonStartupLoader";
import { TicketBadge } from "./tickets/TicketBadge";
import { ArchiveTicketItem } from "./tickets/ArchiveTicketItem";
import { useShellMaybe } from "../lib/shell-context";
import { dotGlow } from "../theme/effects";
import { useTicketsQuery } from "../hooks/useTicketsQuery";
import { isTicketInArchive } from "../lib/ticket-presentation";
import { LANE_DROP_ID } from "../lib/ticket-assign";
import { PlannedColumn } from "./tickets/PlannedColumn";
import { CreateTicketSheet } from "./tickets/CreateTicketSheet";
import { useTicketDrag, useTicketDropTarget } from "./tickets/TicketDndProvider";

type SessionsBoardProps = {
	/** When set, the board shows only this project's sessions. */
	projectId?: string;
};

// Live merged sessions remain in-flow. A terminated runtime is archived even
// when its SCM outcome remains `merged`.
type Column = AttentionZoneView;
type UsageBySession = ReadonlyMap<string, SessionUsageSummary>;
const emptyUsageBySession: UsageBySession = new Map();

function isArchivedSession(session: WorkspaceSession): boolean {
	return session.isTerminated === true || session.status === "terminated";
}

export function SessionsBoard({ projectId }: SessionsBoardProps) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const queryClient = useQueryClient();
	const COLUMNS: Column[] = boardAttentionZoneOrder.map((zone) => getAttentionZoneViewForZone(zone, t));
	const restoreSessionById = useRestoreSession();
	const workspaceQuery = useWorkspaceQuery();
	const shell = useShellMaybe();
	const usageBySession = useSessionUsageSummaries(projectId).data ?? emptyUsageBySession;
	// Evaluated at render so platform mocks in tests can flip the in-panel chrome.
	const all = workspaceQuery.data ?? [];
	const workspaces = projectId ? all.filter((w) => w.id === projectId) : all;
	const sessions = workspaces.flatMap((w) => w.sessions);
	const ticketProjects = workspaces
		.filter((w) => w.kind === "single_repo")
		.map((w) => ({ id: w.id, name: w.name }));
	const ticketsQuery = useTicketsQuery(ticketProjects);
	const openTickets = ticketsQuery.tickets.filter((ticket) => !isTicketInArchive(ticket));
	const archivedTickets = ticketsQuery.tickets.filter(isTicketInArchive);
	const supportsTickets = ticketProjects.length > 0;
	const { active: draggingPlan } = useTicketDrag();
	const sessionsById = new Map<string, WorkspaceSession>();
	for (const w of workspaces) {
		for (const s of w.sessions) sessionsById.set(s.id, s);
	}
	const [createTicketOpen, setCreateTicketOpen] = useState(false);
	const requestNewTask = useUiStore((state) => state.requestNewTask);

	const archived = sessions
		.filter(isArchivedSession)
		.sort((left, right) => right.updatedAt.localeCompare(left.updatedAt));
	const archivedCount = archived.length + archivedTickets.length;
	const byZone = new Map<AttentionZone, WorkspaceSession[]>();
	for (const session of sessions.filter((candidate) => !isArchivedSession(candidate))) {
		const zone = attentionZone(session);
		(byZone.get(zone) ?? byZone.set(zone, []).get(zone)!).push(session);
	}
	// First-run orientation replaces the empty column shells (only once the
	// query has resolved, so the welcome never flashes over real data): the
	// global board teaches the app before any project exists, and a fresh
	// project board invites the first task instead of showing four zeros.
	const isDaemonReady = usesPreviewWorkspaceData || (shell ? shell.daemonStatus.state === "ready" : true);
	const daemonHasFailed = Boolean(shell?.daemonStatus.code);
	const workspaceStartupState = shell?.workspaceStartupState ?? "ready";
	const isLoaded = isDaemonReady && workspaceStartupState === "ready" && workspaceQuery.isSuccess;
	const showStartup =
		shell !== null &&
		!daemonHasFailed &&
		(!isDaemonReady || workspaceStartupState === "loading" || (!workspaceQuery.isSuccess && !workspaceQuery.isError));
	const showWelcome = !projectId && isLoaded && all.length === 0;
	const showProjectEmpty =
		projectId !== undefined && isLoaded && workspaces.length > 0 && sessions.length === 0 && openTickets.length === 0;
	// Archived sessions cost one quiet line under the board until expanded.
	const [archiveExpanded, setArchiveExpanded] = useState(false);
	const [restoringSessionId, setRestoringSessionId] = useState<string | undefined>();
	const [restoreErrors, setRestoreErrors] = useState<Record<string, string>>({});
	const [restoreUnavailableSession, setRestoreUnavailableSession] = useState<WorkspaceSession | undefined>();
	const terminateSession = useTerminateSession();
	const activeProjectIdRef = useRef(projectId);
	activeProjectIdRef.current = projectId;
	useEffect(() => {
		setRestoringSessionId(undefined);
		setRestoreErrors({});
		setRestoreUnavailableSession(undefined);
	}, [projectId]);

	const openSession = (session: WorkspaceSession) =>
		void navigate({
			to: "/projects/$projectId/sessions/$sessionId",
			params: { projectId: session.workspaceId, sessionId: session.id },
		});

	const restoreArchivedSession = async (event: MouseEvent<HTMLButtonElement>, session: WorkspaceSession) => {
		event.stopPropagation();
		if (restoringSessionId) return;
		const restoreProjectId = projectId;
		const isStillActiveProject = () => !restoreProjectId || activeProjectIdRef.current === restoreProjectId;
		setRestoringSessionId(session.id);
		setRestoreErrors((current) => {
			const next = { ...current };
			delete next[session.id];
			return next;
		});
		try {
			const result = await restoreSessionById(session.id);
			if (!isStillActiveProject()) return;
			if (result.status === "success") {
				void navigate({
					to: "/projects/$projectId/sessions/$sessionId",
					params: { projectId: session.workspaceId, sessionId: session.id },
				});
				return;
			}
			if (result.status === "not_resumable") {
				setRestoreUnavailableSession(session);
				return;
			}
			setRestoreErrors((current) => ({ ...current, [session.id]: result.message }));
		} finally {
			if (isStillActiveProject()) {
				setRestoringSessionId(undefined);
			}
		}
	};

	return (
		<div
			className="flex h-full min-h-0 flex-col bg-background text-foreground"
			data-tauri-drag-region={shellChromeDragRegion()}
			data-testid="board"
		>
			<div className="min-h-0 flex-1 overflow-hidden">
				{showStartup ? (
					<DaemonStartupLoader />
				) : workspaceStartupState === "error" || workspaceQuery.isError ? (
					<p className="py-10 text-center text-xs text-passive">{t("shell.couldNotLoadSessions")}</p>
				) : showWelcome ? (
					<BoardWelcome />
				) : showProjectEmpty ? (
					<ProjectBoardEmpty
						onNewTask={() => projectId && requestNewTask(projectId)}
						onNewTicket={supportsTickets ? () => setCreateTicketOpen(true) : undefined}
					/>
				) : (
					<div className="h-full overflow-x-auto overflow-y-hidden">
						{/* Hairline column grid: vertical divide-x + one absolute header rule so
						    the horizontal divider stays continuous and level across lanes.
						    Keep `top-12` aligned with each column header's `h-12`. */}
						<div
							className="relative grid h-full min-w-[80rem] grid-cols-5 divide-x divide-border-strong xl:min-w-0"
							data-board-grid=""
							data-dragging={draggingPlan !== null}
							data-testid="board-grid"
						>
							<div
								aria-hidden="true"
								className="pointer-events-none absolute inset-x-0 top-12 z-10 border-t border-border-strong"
							/>
							<PlannedColumn
								key={`${projectId ?? "all"}:planned`}
								tickets={openTickets}
								projects={ticketProjects}
								sessionsById={sessionsById}
								isError={ticketsQuery.isError}
								supportsTickets={supportsTickets}
								defaultProjectId={projectId}
							/>
							{COLUMNS.map((col) => (
								<BoardColumn
									key={`${projectId ?? "all"}:${col.zone}`}
									col={col}
									sessions={byZone.get(col.zone) ?? []}
									onOpen={openSession}
									onTerminate={(session) => terminateSession.mutate(session)}
									usageBySession={usageBySession}
								/>
							))}
						</div>
					</div>
				)}
			</div>

			{archivedCount > 0 && (
				<div className="shrink-0 border-t border-border-strong px-3">
					{/* The 46px control gives the compact archive bar a slightly taller
					    target while preserving the bar's surrounding row height. */}
					<div className={cn("flex items-center gap-2", archiveExpanded ? "min-h-11" : "min-h-row-md")}>
						<button
							aria-expanded={archiveExpanded}
							aria-label={t("shell.archiveSessionsAria", { count: archivedCount })}
							className="group flex h-[46px] min-w-0 items-center gap-2 py-0 text-muted-foreground transition-colors hover:text-foreground"
							onClick={() => setArchiveExpanded((v) => !v)}
							type="button"
						>
							<svg
								aria-hidden="true"
								className={cn(
									"size-icon-2xs shrink-0 transition-transform duration-normal",
									archiveExpanded && "rotate-90",
								)}
								fill="none"
								stroke="currentColor"
								strokeWidth="2"
								viewBox="0 0 24 24"
							>
								<path d="m9 18 6-6-6-6" />
							</svg>
							<span className="font-mono text-2xs font-medium uppercase tracking-wide-sm">{t("shell.archive")}</span>
							<span className="ml-1.5 font-mono text-micro text-passive">{archivedCount}</span>
						</button>
					</div>
					{archiveExpanded && (
						<div
							aria-label={t("shell.archivedSessions")}
							className="board-scrollbar grid max-h-[45vh] grid-cols-[repeat(auto-fill,minmax(17rem,1fr))] gap-2 overflow-y-auto pb-3"
							role="list"
						>
							{archived.map((s) => (
								<ArchiveSessionItem
									key={s.id}
									session={s}
									restoreAction={(event) => void restoreArchivedSession(event, s)}
									restoreError={restoreErrors[s.id]}
									isRestoring={restoringSessionId === s.id}
									isRestoreDisabled={restoringSessionId !== undefined}
									usage={usageBySession.get(s.id)}
								/>
							))}
							{archivedTickets.map((ticket) => (
								<ArchiveTicketItem key={`${ticket.projectId}:${ticket.slug}`} ticket={ticket} />
							))}
						</div>
					)}
				</div>
			)}
			<CreateTicketSheet
				open={createTicketOpen}
				onOpenChange={setCreateTicketOpen}
				projects={ticketProjects}
				defaultProjectId={projectId}
			/>
			{restoreUnavailableSession && (
				<RestoreUnavailableDialog
					open={true}
					session={restoreUnavailableSession}
					onOpenChange={(open) => {
						if (!open) setRestoreUnavailableSession(undefined);
					}}
					onRecreated={async () => {
						await queryClient.invalidateQueries({ queryKey: workspaceQueryKey });
					}}
				/>
			)}
		</div>
	);
}

function BoardColumn({
	col,
	sessions,
	onOpen,
	onTerminate,
	usageBySession,
}: {
	col: Column;
	sessions: WorkspaceSession[];
	onOpen: (s: WorkspaceSession) => void;
	onTerminate: (s: WorkspaceSession) => void;
	usageBySession: UsageBySession;
}) {
	if (col.zone === "working") {
		return (
			<WorkLaneColumn
				sessions={sessions}
				onOpen={onOpen}
				onTerminate={onTerminate}
				usageBySession={usageBySession}
			/>
		);
	}
	if (col.zone === "merge") {
		return (
			<MergeLaneColumn
				sessions={sessions}
				onOpen={onOpen}
				onTerminate={onTerminate}
				usageBySession={usageBySession}
			/>
		);
	}
	return (
		<ZoneColumn
			col={col}
			sessions={sessions}
			onOpen={onOpen}
			onTerminate={onTerminate}
			usageBySession={usageBySession}
		/>
	);
}

function ZoneColumn({
	col,
	sessions,
	onOpen,
	onTerminate,
	usageBySession,
}: {
	col: Column;
	sessions: WorkspaceSession[];
	onOpen: (s: WorkspaceSession) => void;
	onTerminate: (s: WorkspaceSession) => void;
	usageBySession: UsageBySession;
}) {
	const { t } = useTranslation();
	return (
		<section
			aria-label={t("shell.sessionsAria", { label: col.label })}
			className="flex min-w-0 flex-col overflow-hidden"
			data-testid="board-column"
			data-column={col.zone}
		>
			<div className="flex h-12 shrink-0 items-center gap-2 px-3">
				<span
					className="size-dot-sm rounded-full"
					style={{
						background: col.dot,
						boxShadow: col.dotGlow ? dotGlow(col.dot) : undefined,
					}}
				/>
				<span className={cn("font-mono text-2xs font-medium uppercase tracking-wide-sm", col.titleClassName)}>
					{col.label}
				</span>
				<span className="ml-auto font-mono text-2xs leading-none text-passive">{sessions.length}</span>
			</div>
			<div className="board-scrollbar min-h-0 flex-1 overflow-y-auto px-3 pb-3 pt-3">
				<div className="flex min-h-full flex-col gap-2.5">
					{sessions.map((session) => (
						<SessionCard
							key={session.id}
							session={session}
							onOpen={() => onOpen(session)}
							onTerminate={() => onTerminate(session)}
							usage={usageBySession.get(session.id)}
						/>
					))}
				</div>
			</div>
		</section>
	);
}

type SplitLaneTone = {
	label: string;
	countLabel: string;
	regionLabel: string;
	dotClassName: string;
	titleClassName: string;
	color: string;
	dotGlow: boolean;
};

function splitLaneTones(t: TFunction): {
	idle: SplitLaneTone;
	working: SplitLaneTone;
	ready: SplitLaneTone;
	merged: SplitLaneTone;
} {
	return {
		idle: {
			label: t("status.idle"),
			countLabel: t("shell.countLabel.idle"),
			regionLabel: t("shell.idleSessions"),
			dotClassName: "bg-status-idle",
			titleClassName: "text-status-idle",
			color: "var(--color-status-idle)",
			dotGlow: false,
		},
		working: {
			label: t("status.working"),
			countLabel: t("shell.countLabel.working"),
			regionLabel: t("shell.workingSessions"),
			dotClassName: "bg-status-working",
			titleClassName: "text-status-working",
			color: "var(--color-status-working)",
			dotGlow: true,
		},
		ready: {
			label: t("zone.merge"),
			countLabel: t("shell.countLabel.readyToMerge"),
			regionLabel: t("shell.readyToMergeSessions"),
			dotClassName: "bg-status-ready",
			titleClassName: "text-status-ready",
			color: "var(--color-status-ready)",
			dotGlow: true,
		},
		merged: {
			label: t("status.merged"),
			countLabel: t("shell.countLabel.merged"),
			regionLabel: t("shell.mergedSessions"),
			dotClassName: "bg-status-merged",
			titleClassName: "text-status-merged",
			color: "var(--color-status-merged)",
			dotGlow: false,
		},
	};
}

function WorkLaneColumn({
	sessions,
	onOpen,
	onTerminate,
	usageBySession,
}: {
	sessions: WorkspaceSession[];
	onOpen: (s: WorkspaceSession) => void;
	onTerminate: (s: WorkspaceSession) => void;
	usageBySession: UsageBySession;
}) {
	const { t } = useTranslation();
	const tones = splitLaneTones(t);
	const idleSessions = sessions.filter(isSessionIdle);
	const workingSessions = sessions.filter((session) => !isSessionIdle(session));
	const dropTarget = useTicketDropTarget(LANE_DROP_ID);

	return (
		<SplitLaneColumn
			ariaLabel={t("shell.idleWorkingSessions")}
			zone="working"
			primarySessions={idleSessions}
			primaryTone={tones.idle}
			secondarySessions={workingSessions}
			secondaryTone={tones.working}
			onOpen={onOpen}
			onTerminate={onTerminate}
			usageBySession={usageBySession}
			dropTarget={dropTarget}
		/>
	);
}

function MergeLaneColumn({
	sessions,
	onOpen,
	onTerminate,
	usageBySession,
}: {
	sessions: WorkspaceSession[];
	onOpen: (s: WorkspaceSession) => void;
	onTerminate: (s: WorkspaceSession) => void;
	usageBySession: UsageBySession;
}) {
	const { t } = useTranslation();
	const tones = splitLaneTones(t);
	const mergedSessions = sessions
		.filter((session) => session.status === "merged")
		.sort((left, right) => right.updatedAt.localeCompare(left.updatedAt));
	const readySessions = sessions
		.filter((session) => session.status !== "merged")
		.sort((left, right) => right.updatedAt.localeCompare(left.updatedAt));

	return (
		<SplitLaneColumn
			ariaLabel={t("shell.readyMergedSessions")}
			zone="merge"
			primarySessions={readySessions}
			primaryTone={tones.ready}
			secondarySessions={mergedSessions}
			secondaryTone={tones.merged}
			onOpen={onOpen}
			onTerminate={onTerminate}
			usageBySession={usageBySession}
		/>
	);
}

function SplitLaneColumn({
	ariaLabel,
	zone,
	primarySessions,
	primaryTone,
	secondarySessions,
	secondaryTone,
	onOpen,
	onTerminate,
	usageBySession,
	dropTarget,
}: {
	ariaLabel: string;
	zone: Extract<AttentionZone, "working" | "merge">;
	primarySessions: WorkspaceSession[];
	primaryTone: SplitLaneTone;
	secondarySessions: WorkspaceSession[];
	secondaryTone: SplitLaneTone;
	onOpen: (s: WorkspaceSession) => void;
	onTerminate: (s: WorkspaceSession) => void;
	usageBySession: UsageBySession;
	dropTarget?: { setNodeRef: (node: HTMLElement | null) => void; isOver: boolean; accepts: boolean; dragging: boolean };
}) {
	const { t } = useTranslation();
	const showPrimary = primarySessions.length > 0;
	const showSecondary = secondarySessions.length > 0;

	return (
		<section
			ref={dropTarget?.setNodeRef}
			aria-label={ariaLabel}
			className="flex min-w-0 flex-col overflow-hidden"
			data-column={zone}
			data-drop-accepts={dropTarget?.accepts ?? false}
			data-drop-over={dropTarget?.isOver ?? false}
			data-testid="board-column"
		>
			<div className="flex h-12 shrink-0 items-center gap-2 px-3">
				<div
					aria-label={t("shell.laneSummaryAria", { primary: primaryTone.label, secondary: secondaryTone.label })}
					className="flex min-w-0 items-center gap-2 font-mono text-2xs font-medium uppercase tracking-wide-sm"
					role="group"
				>
					<LaneStatusLabel tone={primaryTone} />
					<span className="text-passive" aria-hidden="true">
						/
					</span>
					<LaneStatusLabel tone={secondaryTone} />
				</div>
				<div className="ml-auto flex shrink-0 items-center gap-2 font-mono text-2xs leading-none text-passive">
					<SessionCount count={primarySessions.length} label={primaryTone.countLabel} />
					<span aria-hidden="true">/</span>
					<SessionCount count={secondarySessions.length} label={secondaryTone.countLabel} />
				</div>
			</div>
			<div className="board-scrollbar min-h-0 flex-1 overflow-y-auto px-3 pb-3 pt-3">
				<div
					className={cn(
						"flex min-h-full flex-col transition-[background-color,outline-color] duration-150",
						dropTarget?.accepts && "rounded-lg outline-dashed outline-1 -outline-offset-4 outline-border-strong",
						dropTarget?.isOver && "bg-interactive-hover/40",
					)}
				>
					{showPrimary ? (
						<div
							aria-label={primaryTone.regionLabel}
							className={cn("flex flex-col", showSecondary ? "flex-none pb-3" : "flex-1")}
							role="region"
						>
							<div className="flex flex-col gap-2.5">
								{primarySessions.map((session) => (
									<SessionCard
										key={session.id}
										session={session}
										onOpen={() => onOpen(session)}
										onTerminate={() => onTerminate(session)}
										usage={usageBySession.get(session.id)}
									/>
								))}
							</div>
						</div>
					) : null}
					{showSecondary ? (
						<SecondaryLaneSection
							sessions={secondarySessions}
							standalone={!showPrimary}
							tone={secondaryTone}
							onOpen={onOpen}
							onTerminate={onTerminate}
							usageBySession={usageBySession}
						/>
					) : null}
					{dropTarget?.accepts ? (
						<p className="mt-auto pt-3 text-center text-2xs font-medium text-muted-foreground" role="status">
							{t("tickets.dropToAssign")}
						</p>
					) : null}
				</div>
			</div>
		</section>
	);
}

function LaneStatusLabel({ tone }: { tone: SplitLaneTone }) {
	return (
		<span className={cn("inline-flex shrink-0 items-center gap-2 whitespace-nowrap", tone.titleClassName)}>
			<span
				className={cn("size-dot-sm rounded-full", tone.dotClassName)}
				style={{ boxShadow: tone.dotGlow ? dotGlow(tone.color) : undefined }}
				aria-hidden="true"
			/>
			{tone.label}
		</span>
	);
}

function SessionCount({ count, label }: { count: number; label: string }) {
	const { t } = useTranslation();
	return <span aria-label={t("shell.countSessionsAria", { count, label })}>{count}</span>;
}

function SecondaryLaneSection({
	sessions,
	onOpen,
	onTerminate,
	standalone,
	tone,
	usageBySession,
}: {
	sessions: WorkspaceSession[];
	onOpen: (s: WorkspaceSession) => void;
	onTerminate?: (s: WorkspaceSession) => void;
	standalone: boolean;
	tone: SplitLaneTone;
	usageBySession: UsageBySession;
}) {
	return (
		<div
			aria-label={tone.regionLabel}
			className={cn(
				"overflow-hidden",
				standalone ? "flex flex-1 flex-col" : "flex flex-1 flex-col border-t border-border-strong",
			)}
			role="region"
		>
			<div className="flex shrink-0 items-center gap-2 px-3 py-2.5">
				<div className="font-mono text-2xs font-medium uppercase tracking-wide-sm">
					<LaneStatusLabel tone={tone} />
				</div>
				<span className="ml-auto font-mono text-2xs leading-none text-passive">{sessions.length}</span>
			</div>
			<div className="flex flex-col gap-2.5 pt-3">
				{sessions.map((session) => (
					<SessionCard
						key={session.id}
						session={session}
						onOpen={() => onOpen(session)}
						onTerminate={onTerminate ? () => onTerminate(session) : undefined}
						usage={usageBySession.get(session.id)}
					/>
				))}
			</div>
		</div>
	);
}

function SessionCard({
	session,
	onOpen,
	onTerminate,
	usage,
	interactive = true,
	action,
	branchAction,
	footer,
}: {
	session: WorkspaceSession;
	onOpen?: () => void;
	onTerminate?: () => void;
	usage?: SessionUsageSummary;
	interactive?: boolean;
	action?: ReactNode;
	branchAction?: ReactNode;
	footer?: ReactNode;
}) {
	const { t } = useTranslation();
	const queryClient = useQueryClient();
	const [confirmOpen, setConfirmOpen] = useState(false);
	const { mutate: openShellTerminal, isPending: isOpeningShell } = useOpenShellTerminal();
	const setActiveShellTerminal = useUiStore((state) => state.setActiveShellTerminal);
	const badge = getSessionStatusView(session.status, t);
	const activity = getAgentActivityView(session.activity, t);
	const showLiveActivity = session.status === "working" && activity.state === "active";
	const issueId = canonicalTrackerIssueId(session.issueId);
	const branch = session.branch || "";
	const showBranch = branch !== "" && !sameLabel(branch, session.title) && !sameLabel(branch, session.id);
	const inPlace = session.workspaceMode === "in_place";
	const workspacePath = session.workspacePath || "";
	const rawLocation = workspacePath.split("/").filter(Boolean).pop() || "";
	const location =
		rawLocation !== "" && !sameLabel(rawLocation, session.title) && !sameLabel(rawLocation, session.id)
			? rawLocation
			: "";
	const showLocation = showBranch || location !== "";
	const prSummaries = sessionPRDisplaySummaries(session, useSessionScmSummary(session.id).data);
	const termination = useTerminateSessionState(session.id);
	const showTerminate = interactive && session.isTerminated !== true && onTerminate;
	// Same action as the sidebar row's: the daemon owns where the session lives,
	// so this sends an id and never a path. A terminated session has no workspace
	// left to open a shell in.
	const showOpenTerminal = interactive && session.isTerminated !== true && onOpen;
	// The title clears whatever the corner cluster occupies: one control, two, or
	// just the `action` slot.
	const cornerControlPadding = action
		? "pr-6"
		: showOpenTerminal && showTerminate
			? "pr-16"
			: showOpenTerminal || showTerminate
				? "pr-8"
				: undefined;
	const openTerminal = () => {
		openShellTerminal(
			{ sessionId: session.id },
			{
				onSuccess: (shell) => {
					setActiveShellTerminal(shell.handleId);
					onOpen?.();
				},
			},
		);
	};
	const handleKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
		if (!interactive || !onOpen) return;
		if (event.currentTarget !== event.target) return;
		if (event.key !== "Enter" && event.key !== " ") return;
		event.preventDefault();
		onOpen();
	};
	const cardBodyProps = interactive
		? {
				onClick: onOpen,
				onKeyDown: handleKeyDown,
				role: "button",
				tabIndex: 0,
			}
		: { role: "listitem" };
	return (
		<div
			{...cardBodyProps}
			className={cn(
				"group relative w-full rounded-xl border text-left transition-[border-color,box-shadow]",
				badge.cardClassName ?? "border-border bg-surface",
				interactive && "cursor-pointer hover:border-border-strong hover:shadow-sm",
			)}
			data-testid="board-session-card"
			data-session-id={session.id}
		>
			{/* One cluster, so the terminal and kill controls share a baseline by
			    construction instead of by matching offsets in two places. */}
			{showOpenTerminal || showTerminate ? (
				<div className="absolute right-2 top-1.5 z-10 flex items-center gap-0.5">
					{showOpenTerminal ? (
						<button
							aria-label={t("shell.openSessionTerminal", { title: session.title })}
							className="inline-flex size-control-md items-center justify-center rounded-sm text-passive transition-colors hover:bg-interactive-hover hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/60"
							disabled={isOpeningShell}
							onClick={(event) => {
								event.stopPropagation();
								openTerminal();
							}}
							title={t("shell.openSessionTerminalAction")}
							type="button"
						>
							<SquareTerminal aria-hidden="true" className="size-icon-sm" />
						</button>
					) : null}
					{showTerminate ? (
						<SessionTerminationPopover
							onConfirm={() => {
								setConfirmOpen(false);
								onTerminate();
							}}
							onOpenChange={setConfirmOpen}
							open={confirmOpen}
							session={session}
							trigger={
								<button
									aria-label={
										termination.isPending
											? t("shell.killingNamedAria", { title: session.title })
											: t("shell.terminateNamed", { title: session.title })
									}
									className="inline-flex size-control-md items-center justify-center rounded-sm text-passive transition-[color,background-color] hover:bg-error/10 hover:text-error focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/60"
									onClick={(event) => {
										event.stopPropagation();
										clearTerminateSessionState(queryClient, session.id);
									}}
									disabled={termination.isPending}
									title={termination.isPending ? t("shell.killingSession") : t("shell.terminateSession")}
									type="button"
								>
									{termination.isPending ? (
										<LoaderCircle className="size-icon-sm animate-spin" aria-hidden="true" />
									) : (
										<Trash2 className="size-icon-sm" aria-hidden="true" />
									)}
								</button>
							}
						/>
					) : null}
				</div>
			) : null}
			{action ? <div className="absolute right-2 top-1.5 z-10">{action}</div> : null}
			<div className="flex items-start gap-2.5 px-3.5 pb-2.5 pt-3">
				<AgentAvatar className="mt-0.5" provider={session.provider} />
				<div className="min-w-0 flex-1">
					<div
						className={cn(
							"line-clamp-2 overflow-hidden text-base font-semibold leading-tight tracking-tight text-foreground",
							cornerControlPadding,
						)}
						title={session.title}
					>
						{session.title}
					</div>
					{showLocation && (
						<div className="mt-1.5 flex min-w-0 items-center gap-1 font-mono text-micro leading-normal text-passive">
							{showBranch && (
								<span className="flex min-w-0 items-center gap-1" title={branch}>
									<GitBranch aria-hidden="true" className="size-icon-2xs shrink-0 opacity-60" />
									<span className="min-w-0 truncate">{branch}</span>
								</span>
							)}
							{location !== "" && (
								<span
									className={cn(
										"inline-flex max-w-[55%] shrink-0 items-center gap-1 rounded-sm px-1 py-px",
										inPlace ? "bg-warning/10 text-warning" : "text-passive/70",
									)}
									data-testid={inPlace ? "session-location-in-place" : undefined}
									title={workspacePath}
								>
									{inPlace && <FolderOpen aria-hidden="true" className="size-icon-2xs shrink-0" />}
									<span className="truncate">{location}</span>
								</span>
							)}
							{branchAction}
						</div>
					)}
					<SessionClaudeAccountChip
						className="mt-1 rounded-sm border border-border bg-surface px-1 py-px text-micro text-passive"
						session={session}
					/>
				</div>
			</div>
			<div aria-hidden="true" className="mx-3.5 my-px h-px bg-border" />
			<div className="flex flex-col gap-1.5 px-3.5 py-2">
				<div className="flex items-center justify-between gap-2">
					<span
						className={cn("inline-flex min-w-0 items-center gap-1.5 truncate text-2xs font-medium", badge.className)}
						style={showLiveActivity ? { color: activity.tone } : undefined}
					>
						<span
							aria-hidden="true"
							className={cn(
								"size-dot-sm shrink-0 rounded-full",
								showLiveActivity ? activity.indicatorClassName : "bg-current",
							)}
						/>
						{badge.label}
					</span>
					<div className="ml-auto flex shrink-0 items-center gap-1.5 whitespace-nowrap font-mono text-2xs text-passive">
						<SessionUsageMetric usage={usage} />
						{usage && usage.totalTokens > 0 ? <span aria-hidden="true">·</span> : null}
						<span title={t("shell.updatedAt", { time: session.updatedAt })}>
							{formatTimeCompact(session.updatedAt)}
						</span>
					</div>
				</div>
				{prSummaries.length > 0 && (
					<div className="flex flex-wrap items-center gap-x-2 gap-y-1 font-mono text-2xs text-passive">
						{groupPRsByLifecycle(prSummaries).map((group) => (
							<BoardPRGroup group={group} key={group.status.label} />
						))}
					</div>
				)}
				{issueId && (
					<span
						className="inline-flex max-w-branch-chip items-center self-start truncate rounded-sm border border-border bg-surface px-1.5 py-0.5 font-mono text-micro text-muted-foreground"
						title={t("shell.intakeIssue", { id: issueId })}
					>
						{issueId}
					</span>
				)}
				{session.ticket ? (
					<TicketBadge className="self-start" projectId={session.workspaceId} ticket={session.ticket} />
				) : null}
			</div>
			{termination.error ? (
				<div className="border-t border-border px-3.5 py-1.5 text-2xs text-destructive" role="alert">
					{termination.error}
				</div>
			) : null}
			{footer}
		</div>
	);
}

function ArchiveSessionItem({
	session,
	restoreAction,
	restoreError,
	isRestoring,
	isRestoreDisabled,
	usage,
}: {
	session: WorkspaceSession;
	restoreAction: (event: MouseEvent<HTMLButtonElement>) => void;
	restoreError?: string;
	isRestoring: boolean;
	isRestoreDisabled: boolean;
	usage?: SessionUsageSummary;
}) {
	const branch = session.branch || "";
	const restoreButton = (
		<ArchiveRestoreButton
			isDisabled={isRestoreDisabled}
			isRestoring={isRestoring}
			label={`Restore ${session.title}`}
			onClick={restoreAction}
		/>
	);

	return (
		<SessionCard
			action={restoreButton}
			branchAction={branch ? <CopyActionButton label={`branch ${branch}`} value={branch} /> : undefined}
			footer={<ArchiveRestoreError message={restoreError} />}
			interactive={false}
			session={session}
			usage={usage}
		/>
	);
}

function SessionUsageMetric({ usage }: { usage?: SessionUsageSummary }) {
	const { t } = useTranslation();
	if (!usage || usage.totalTokens <= 0) return null;
	const tooltip = t("shell.usageTokens", {
		count: usage.totalTokens.toLocaleString("en-US"),
	});
	return (
		<Tooltip>
			<TooltipTrigger asChild>
				<span
					aria-label={tooltip}
					className="inline-flex shrink-0 items-center gap-1 whitespace-nowrap font-mono text-2xs text-muted-foreground"
				>
					{formatTokenCount(usage.totalTokens)}
				</span>
			</TooltipTrigger>
			<TooltipContent side="top">{tooltip}</TooltipContent>
		</Tooltip>
	);
}

function ArchiveRestoreButton({
	label,
	onClick,
	isRestoring,
	isDisabled,
}: {
	label: string;
	onClick: (event: MouseEvent<HTMLButtonElement>) => void;
	isRestoring: boolean;
	isDisabled: boolean;
}) {
	const { t } = useTranslation();
	return (
		<Tooltip>
			<TooltipTrigger asChild>
				<button
					aria-label={label}
					className="grid size-control-board-sm shrink-0 place-items-center rounded-md text-passive transition-colors hover:bg-interactive-hover hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-accent/50 disabled:cursor-not-allowed disabled:opacity-35"
					disabled={isDisabled}
					onClick={onClick}
					type="button"
				>
					<RotateCcw className={cn("size-icon-md", isRestoring && "animate-spin")} aria-hidden="true" />
				</button>
			</TooltipTrigger>
			<TooltipContent side="top">{isRestoring ? t("shell.restoringSession") : t("shell.restoreSession")}</TooltipContent>
		</Tooltip>
	);
}

function ArchiveRestoreError({ message }: { message?: string }) {
	return message ? (
		<div className="border-t border-border px-2 py-1.5 text-2xs text-destructive" role="alert">
			{message}
		</div>
	) : null;
}

type BoardPRLifecycleStatus = { label: "closed" | "open" | "draft" | "merged"; className: string };
type BoardPRGroup = { status: BoardPRLifecycleStatus; prs: SessionPRSummary[] };

function BoardPRGroup({ group }: { group: BoardPRGroup }) {
	const { t } = useTranslation();
	const statusLabel = t(`pr.state.${group.status.label}`);
	return (
		<span
			aria-label={`${group.prs.map((pr) => `#${pr.number}`).join(", ")} ${statusLabel}`}
			className="inline-flex min-w-0 flex-wrap items-center gap-x-1.5 gap-y-1"
		>
			<span>{t("pr.short")}</span>
			{group.prs.map((pr, index) => (
				<span className="inline-flex items-center" key={pr.url || pr.htmlUrl || pr.number}>
					<a
						className="text-passive underline-offset-2 transition-colors hover:text-foreground hover:underline"
						href={prBrowserUrl(pr)}
						onClick={(event) => event.stopPropagation()}
						rel="noreferrer"
						target="_blank"
					>
						#{pr.number}
					</a>
					{index < group.prs.length - 1 ? "," : null}
				</span>
			))}
			<span className={cn("font-medium", group.status.className)}>{statusLabel}</span>
		</span>
	);
}

function CopyActionButton({ label, value }: { label: string; value: string }) {
	const [copied, setCopied] = useState(false);
	const copiedTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
	useEffect(
		() => () => {
			if (copiedTimeoutRef.current !== null) clearTimeout(copiedTimeoutRef.current);
		},
		[],
	);
	const buttonLabel = copied ? `Copied ${label}` : `Copy ${label}`;
	const copyValue = async (event: MouseEvent<HTMLButtonElement>) => {
		event.stopPropagation();
		try {
			await operatorBridge.clipboard.writeText(value);
		} catch {
			return;
		}
		setCopied(true);
		if (copiedTimeoutRef.current !== null) clearTimeout(copiedTimeoutRef.current);
		copiedTimeoutRef.current = setTimeout(() => {
			setCopied(false);
			copiedTimeoutRef.current = null;
		}, 1_500);
	};
	return (
		<button
			aria-label={buttonLabel}
			className="inline-flex size-4 shrink-0 items-center justify-center rounded-sm text-passive transition-colors hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
			onClick={(event) => void copyValue(event)}
			title={buttonLabel}
			type="button"
		>
			{copied ? (
				<Check className="size-icon-2xs text-success" aria-hidden="true" />
			) : (
				<Copy className="size-icon-2xs" aria-hidden="true" />
			)}
		</button>
	);
}

function groupPRsByLifecycle(prs: SessionPRSummary[]): BoardPRGroup[] {
	const groups = new Map<BoardPRLifecycleStatus["label"], BoardPRGroup>();
	for (const pr of prs) {
		const status = prLifecycleStatus(pr);
		const group = groups.get(status.label);
		if (group) {
			group.prs.push(pr);
		} else {
			groups.set(status.label, { status, prs: [pr] });
		}
	}
	return Array.from(groups.values());
}

function prLifecycleStatus(pr: SessionPRSummary): BoardPRLifecycleStatus {
	if (pr.state === "draft") return { label: "draft", className: "text-passive" };
	if (pr.state === "merged") return { label: "merged", className: "text-status-merged" };
	if (pr.state === "closed") return { label: "closed", className: "text-error" };
	return { label: "open", className: "text-success" };
}

function sameLabel(a: string, b: string): boolean {
	const normalize = (value: string) =>
		value
			.toLowerCase()
			.replace(/^(feat|fix|chore|refactor|session)\//, "")
			.replace(/[^a-z0-9]+/g, "");
	return normalize(a) === normalize(b);
}
