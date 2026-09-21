import { useTranslation } from "react-i18next";
import { useParams } from "@tanstack/react-router";
import { GitBranch, PanelRightClose, PanelRightOpen, Plus, SquareTerminal } from "lucide-react";
import { LayoutGroup, motion } from "motion/react";
import type { WorkspaceSession } from "../types/workspace";
import { useWorkspaceQuery } from "../hooks/useWorkspaceQuery";
import { inspectorState, useUiStore } from "../stores/ui-store";
import { getAgentActivityView } from "../lib/session-presentation";
import { isMacPlatform, usesBoardActionsInPanel, windowDragRegion } from "../lib/platform";
import { SessionClaudeAccountMenu } from "./SessionClaudeAccountMenu";
import { StatusPill } from "./StatusPill";
import { BoardDiff, TopbarButton, topbarHeaderClass, topbarProjectLabelClass } from "./TopbarButton";
import { TicketBadge } from "./tickets/TicketBadge";

const isMac = isMacPlatform();
const boardActionsInPanel = usesBoardActionsInPanel();
const dragRegion = windowDragRegion();

// The one app topbar (.dashboard-app-header). On Win/Linux the shell mounts it
// inside the framed center panel; when the platform hides the shell topbar
// (macOS), SessionView mounts the same component in-panel so Kill / inspector
// stay available. The variant is derived from the route, not props: a
// sessionId in the URL swaps the lead to the session identity (worker branch +
// status pill) and the actions to board + inspector controls; otherwise it's
// the dashboard crumb plus board actions when a project is in scope.
export function ShellTopbar({ embedded = false }: { embedded?: boolean } = {}) {
	const { t } = useTranslation();
	const params = useParams({ strict: false }) as { projectId?: string; sessionId?: string };
	const currentSessionId = params.sessionId;
	const isInspectorOpen = useUiStore((state) =>
		currentSessionId ? inspectorState(state.inspectorSessions, currentSessionId).isOpen : false,
	);
	const toggleInspector = useUiStore((state) => state.toggleInspector);
	const requestNewTask = useUiStore((state) => state.requestNewTask);
	const requestNewShellTerminal = useUiStore((state) => state.requestNewShellTerminal);
	const all = useWorkspaceQuery().data ?? [];

	const session = params.sessionId
		? all.flatMap((workspace) => workspace.sessions).find((s) => s.id === params.sessionId)
		: undefined;
	const isSessionRoute = Boolean(params.sessionId);
	// Project in scope: the session's workspace wins over the route param so the
	// cross-project /sessions/$sessionId route still resolves a crumb. A
	// projectId that no longer resolves (stale route after the project was
	// removed, or data still loading) shows an empty crumb — never the raw
	// route slug. "Board" is the root-board crumb only.
	const projectId = session?.workspaceId ?? params.projectId;
	const isProjectBoardRoute = !isSessionRoute && Boolean(projectId);
	const isRootBoardRoute = !isSessionRoute && !isProjectBoardRoute;
	const project = projectId ? all.find((workspace) => workspace.id === projectId) : undefined;
	const projectLabel = project?.name ?? session?.workspaceName ?? (projectId ? "" : t("shell.board"));

	const openNewTask = () => {
		if (!projectId) return;
		requestNewTask(projectId);
	};

	const handleToggleInspector = () => {
		if (!currentSessionId) return;
		toggleInspector(currentSessionId);
	};

	return (
		<LayoutGroup id="shell-topbar">
		<motion.header
			className={embedded ? "contents" : topbarHeaderClass}
			data-tauri-drag-region={embedded ? undefined : dragRegion}
			style={embedded ? undefined : { paddingLeft: 18 }}
		>
			{!embedded ? (
				<div className="flex min-w-0 items-center gap-3">
				{isSessionRoute ? (
						<div className="flex min-w-0 items-center gap-3">
							{session?.branch ? (
								<div className="inline-flex min-w-0 items-center gap-1 font-mono text-2xs leading-none text-passive">
									<GitBranch className="size-icon-2xs shrink-0" aria-hidden="true" />
									<span className="truncate">{session.branch}</span>
								</div>
							) : null}
							{session?.ticket ? <TicketBadge projectId={session.workspaceId} ticket={session.ticket} /> : null}
							{session ? <SessionStatusPill session={session} /> : null}
						</div>
					) : (isProjectBoardRoute && boardActionsInPanel) ||
				  (isMac && isRootBoardRoute && boardActionsInPanel) ? null : (
					<div className="inline-flex min-w-0 items-center gap-1.5">
						<motion.span
							layoutId="topbar-project-label"
							layout="position"
							className={topbarProjectLabelClass}
							transition={{ type: "spring", stiffness: 400, damping: 40 }}
						>
							{projectLabel}
						</motion.span>
					</div>
				)}
				</div>
			) : null}

			{!embedded ? <div className="min-w-0 flex-1" /> : null}

			<div className="flex shrink-0 items-center gap-1.5">
				{!isSessionRoute && <BoardDiff workspaces={project ? [project] : all} />}
				{!boardActionsInPanel && isProjectBoardRoute ? (
					<>
						<TopbarButton
							aria-label={t("shortcut.new-shell-terminal")}
							onClick={requestNewShellTerminal}
						>
							<SquareTerminal className="size-icon-lg" aria-hidden="true" />
							{t("shortcut.new-shell-terminal")}
						</TopbarButton>
						<TopbarButton
							aria-label={t("shell.newTask")}
							onClick={openNewTask}
							variant="accent"
						>
							<Plus className="size-icon-lg" aria-hidden="true" />
							{t("shell.newTask")}
						</TopbarButton>
					</>
				) : null}
				{isSessionRoute ? (
					<>
						{session ? (
							<SessionClaudeAccountMenu
								className="h-control-sm rounded-md border border-border bg-surface px-2 text-micro font-semibold tracking-wide-sm text-muted-foreground hover:text-foreground"
								session={session}
							/>
						) : null}
						<TopbarButton
							aria-label={isInspectorOpen ? t("shell.closeInspector") : t("shell.openInspector")}
							aria-pressed={isInspectorOpen}
							onClick={handleToggleInspector}
							title={isInspectorOpen ? t("shell.closeInspectorTitle") : t("shell.openInspectorTitle")}
							variant="icon"
						>
							{isInspectorOpen ? (
								<PanelRightClose className="size-5" aria-hidden="true" />
							) : (
								<PanelRightOpen className="size-5" aria-hidden="true" />
							)}
						</TopbarButton>
					</>
				) : null}
			</div>
		</motion.header>
	</LayoutGroup>
	);
}

function SessionStatusPill({ session }: { session: WorkspaceSession }) {
	const { t } = useTranslation();
	const { label, tone, breathe } = getAgentActivityView(session.activity, t);
	return (
		<StatusPill label={label} tone={tone} breathe={breathe} leading="none" className="px-3.5 py-2 text-sm" />
	);
}
