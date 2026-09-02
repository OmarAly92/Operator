import { ArrowRight, ChevronLeft, ChevronRight, Plus, TriangleAlert } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { apiClient, apiErrorMessage } from "../lib/api-client";
import { defaultShortcutBindings, shortcutBindingLabel } from "../../shared/shortcuts";
import { useOverflowScroll } from "../hooks/useOverflowScroll";
import {
	findActiveAgentSwitch,
	findRecoveryRequiredAgentSwitch,
	useAgentSwitches,
} from "../hooks/useAgentSwitches";
import { useSwitchAgentState } from "../hooks/useSwitchAgent";
import { useTruncatedText } from "../hooks/useTruncatedText";
import type { ShellTerminal } from "../hooks/useShellTerminals";
import { TERMINAL_FONT_SIZE_DEFAULT, TERMINAL_FONT_SIZE_MAX, TERMINAL_FONT_SIZE_MIN } from "../lib/design-tokens";
import { getAgentActivityView } from "../lib/session-presentation";
import { agentLabel } from "../lib/agent-options";
import { isLinuxPlatform, isMacPlatform } from "../lib/platform";
import { operatorBridge } from "../lib/bridge";
import { handleTerminalTabListKeyDown } from "../lib/terminal-tabs";
import { cn } from "../lib/utils";
import { useUiStore, type Theme } from "../stores/ui-store";
import type { TerminalTarget } from "../types/terminal";
import {
	brokenMcpServers,
	can as snapshotCan,
	type ChatSkill,
	type ConversationActivity,
	type ConversationSnapshot,
} from "../types/conversation";
import { isOrchestratorSession, type WorkspaceSession } from "../types/workspace";
import { AgentAvatar } from "./AgentAvatar";
import { ShellTerminalTab } from "./ShellTerminalTab";
import { TerminalPane } from "./TerminalPane";
import { SessionTopbarPortal } from "./SessionTopbarPortal";
import { TerminalSwitchAgentButton } from "./TerminalSwitchAgentButton";
import { BlockComposer, type BlockComposerSend } from "./blocks/BlockComposer";
import { BlocksView } from "./blocks/BlocksView";
import { useSessionBlocks } from "../hooks/useSessionBlocks";
import {
	useConversation,
	useConversationCommands,
	useConversationConfigOptions,
	useConversationModels,
	useConversationSkills,
	useStageAttachments,
	useWorkspaceFilePaths,
} from "../hooks/useConversation";
import { ElicitationCard } from "./chat/ElicitationCard";
import { McpServerBanner, ReauthBanner, ThreadStateBanner } from "./chat/ChatStatusBanners";
import { TurnSettingsBar } from "./chat/TurnSettingsBar";
import { blocksFromConversation } from "../lib/conversation-blocks";
import type { SessionBlock } from "../lib/session-block";
import { blocksCoverHarness } from "../lib/session-block";
import type { TurnGroup } from "../lib/block-turns";
import type { BlockAction, BlockActionContext } from "../lib/block-actions";
import { MAX_SUGGESTIONS, rankFiles, rankSkills, type Suggestion } from "./chat/composerSuggest";
import { Button } from "./ui/button";
import { Tooltip, TooltipContent, TooltipTrigger } from "./ui/tooltip";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
} from "./ui/dialog";

type CenterPaneProps = {
	session?: WorkspaceSession;
	theme: Theme;
	daemonReady: boolean;
	terminalTarget?: TerminalTarget;
	reviewerTerminal?: { handleId: string; harness: string };
	onSelectReviewerTerminal?: (target: { handleId: string; harness: string }) => void;
	/** Standalone shells to render as tabs beside the session's own pane. */
	shellTerminals?: ShellTerminal[];
	onSelectSessionTerminal?: () => void;
	onSelectShellTerminal?: (handleId: string) => void;
	onCloseShellTerminal?: (handleId: string) => void;
	onRenameShellTerminal?: (handleId: string, title: string) => void;
	/** Opens a new shell tab in this session's worktree (the button at the end of the tab bar). */
	onNewShellTerminal?: () => void;
	/** Session actions consolidated into the terminal bar by SessionView. */
	topbarActions?: ReactNode;
	/** Stop forwarding the agent pane's keystrokes while its controller drains. */
	agentInputDisabled?: boolean;
};

const terminalFontSizeStorageKey = "opr.terminal.fontSize";
const isMac = isMacPlatform();
const isLinux = isLinuxPlatform();
const newTerminalShortcutLabel = shortcutBindingLabel(defaultShortcutBindings("new-shell-terminal", isMac)[0], isMac);

function initialTerminalFontSize(): number {
	if (typeof window === "undefined") return TERMINAL_FONT_SIZE_DEFAULT;
	const raw = window.localStorage?.getItem(terminalFontSizeStorageKey);
	const parsed = raw === null ? Number.NaN : Number(raw);
	if (!Number.isFinite(parsed)) return TERMINAL_FONT_SIZE_DEFAULT;
	return Math.min(TERMINAL_FONT_SIZE_MAX, Math.max(TERMINAL_FONT_SIZE_MIN, parsed));
}

export function CenterPane({
	session,
	theme,
	daemonReady,
	terminalTarget,
	reviewerTerminal,
	onSelectReviewerTerminal,
	shellTerminals = [],
	onSelectSessionTerminal,
	onSelectShellTerminal,
	onCloseShellTerminal,
	onRenameShellTerminal,
	onNewShellTerminal,
	topbarActions,
	agentInputDisabled = false,
}: CenterPaneProps) {
	const { t } = useTranslation();
	const paneRef = useRef<HTMLDivElement | null>(null);
	const [fontSize] = useState(initialTerminalFontSize);
	const [terminalBounds, setTerminalBounds] = useState({ leftInset: 0, rightInset: 0, width: 0 });
	const isSidebarOpen = useUiStore((state) => state.isSidebarOpen);
	const tabOverflowWatch = `${session?.id ?? ""}|${shellTerminals.map((terminal) => terminal.handleId).join("|")}`;
	const tabsOverflow = useOverflowScroll<HTMLDivElement>(tabOverflowWatch);
	const agentSwitchesQuery = useAgentSwitches(session?.id ?? "");
	const agentSwitches = agentSwitchesQuery.data ?? [];
	const activeAgentSwitch = findActiveAgentSwitch(agentSwitches);
	const recoveryAgentSwitch = findRecoveryRequiredAgentSwitch(agentSwitches);
	const switchMutation = useSwitchAgentState(session?.id ?? "");
	const switchSource = recoveryAgentSwitch?.fromHarness ?? activeAgentSwitch?.fromHarness ?? switchMutation.input?.session.provider;
	const switchTarget = recoveryAgentSwitch?.targetHarness ?? activeAgentSwitch?.targetHarness ?? switchMutation.input?.targetHarness;
	const isSwitchingAgent = Boolean(
		!recoveryAgentSwitch && (activeAgentSwitch || switchMutation.isPending) && switchSource && switchTarget,
	);
	const switchNeedsRecovery = Boolean(recoveryAgentSwitch && switchSource && switchTarget);
	const switchPermissionRequired = Boolean(
		activeAgentSwitch?.state === "preparing_handoff" &&
			activeAgentSwitch.agentHandoffStatus === "requested" &&
			(session?.activity?.state === "blocked" || session?.activity?.state === "waiting_input"),
	);
	const target = terminalTarget ?? { kind: "worker" };

	const sessionTabLabel = session
		? isOrchestratorSession(session)
			? t("shell.orchestrator")
			: session.title
		: t("terminal.noSession");
	const activeTerminalLabel =
		target.kind === "shell"
			? (shellTerminals.find((shell) => shell.handleId === target.handleId)?.title ?? target.title)
			: target.kind === "reviewer"
				? `${t("terminal.reviewer")} · ${target.harness}`
				: sessionTabLabel;
	const selectAdjacentTab = useCallback(
		(direction: -1 | 1) => {
			const activeIndex =
				target.kind === "shell"
					? shellTerminals.findIndex((shell) => shell.handleId === target.handleId) + 1
					: 0;
			const nextIndex = (activeIndex + direction + shellTerminals.length + 1) % (shellTerminals.length + 1);
			if (nextIndex === 0) {
				onSelectSessionTerminal?.();
				return;
			}
			const nextShell = shellTerminals[nextIndex - 1];
			if (nextShell) onSelectShellTerminal?.(nextShell.handleId);
		},
		[onSelectSessionTerminal, onSelectShellTerminal, shellTerminals, target],
	);

	useEffect(() => {
		if (!switchMutation.isPending || activeAgentSwitch || recoveryAgentSwitch) return;
		void agentSwitchesQuery.refetch();
		const timer = window.setInterval(() => void agentSwitchesQuery.refetch(), 500);
		return () => window.clearInterval(timer);
	}, [activeAgentSwitch, agentSwitchesQuery.refetch, recoveryAgentSwitch, switchMutation.isPending]);

	useEffect(
		() =>
			operatorBridge.app.onCloseShellTerminalShortcut(() => {
				if (target.kind === "shell") onCloseShellTerminal?.(target.handleId);
			}),
		[target, onCloseShellTerminal],
	);

	useEffect(() => {
		const disposePrevious = operatorBridge.app.onPreviousTabShortcut(() => selectAdjacentTab(-1));
		const disposeNext = operatorBridge.app.onNextTabShortcut(() => selectAdjacentTab(1));
		return () => {
			disposePrevious();
			disposeNext();
		};
	}, [selectAdjacentTab]);

	useEffect(() => {
		operatorBridge.app.setCloseShellTerminalShortcutEnabled(
			target.kind === "shell" && Boolean(onCloseShellTerminal),
		);
		return () => operatorBridge.app.setCloseShellTerminalShortcutEnabled(false);
	}, [target.kind, onCloseShellTerminal]);

	useEffect(() => {
		const pane = paneRef.current;
		if (!pane) return;
		const workspaceSurface = pane.closest<HTMLElement>(".center-panel-surface");
		const measure = () => {
			const paneRect = pane.getBoundingClientRect();
			// leftInset/rightInset are kept for the terminal region width calculation
			// but no longer used for viewport-alignment padding (topbar is inside the surface).
			const workspaceRect = workspaceSurface?.getBoundingClientRect() ?? paneRect;
			const next = {
				leftInset: workspaceRect.left,
				rightInset: Math.max(0, window.innerWidth - workspaceRect.right),
				width: paneRect.width,
			};
			setTerminalBounds((current) =>
				current.leftInset === next.leftInset && current.rightInset === next.rightInset && current.width === next.width
					? current
					: next,
			);
		};
		measure();
		const observer = new ResizeObserver(measure);
		observer.observe(pane);
		if (workspaceSurface) observer.observe(workspaceSurface);
		return () => observer.disconnect();
	}, []);

	const terminalTopbar = (
		<div className="flex h-inspector-tabs w-full shrink-0 items-stretch bg-sidebar">

			<div className="session-topbar-surface flex min-w-0 flex-1" data-testid="session-workspace-topbar">
				<div
					className={cn(
						"flex min-w-0 shrink items-center pr-1.5",
						!isSidebarOpen && isMac && "session-topbar-titlebar-clearance-mac",
						!isSidebarOpen && isLinux && "session-topbar-titlebar-clearance-linux",
					)}
					data-testid="session-terminal-region"
					style={{
						width: terminalBounds.width > 0 ? terminalBounds.width : "100%",
					}}
				>
					<div className="flex h-full min-w-flex-min flex-1 items-center">
						{tabsOverflow.canScrollLeft ? (
							<button
								aria-label={t("terminal.scrollTabsLeft")}
								className="inline-flex size-control-sm shrink-0 items-center justify-center rounded-sm text-muted-foreground transition-colors hover:bg-interactive-hover hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-accent/50"
								onClick={() => tabsOverflow.scrollByDirection(-1)}
								title={t("terminal.scrollTabsLeft")}
								type="button"
							>
								<ChevronLeft aria-hidden="true" className="size-icon-md" />
							</button>
						) : null}
						{/* The permanent agent tab plus shells opened in this session's worktree.
						    It hugs its tabs rather than growing, so the + that follows sits against
						    the last tab; it still shrinks and scrolls once the tabs outgrow the row. */}
						<div
							ref={tabsOverflow.ref}
							aria-label={t("terminal.tabsAria")}
							className="scrollbar-none flex min-w-flex-min shrink self-stretch items-center overflow-x-auto"
							onKeyDown={handleTerminalTabListKeyDown}
							role="tablist"
						>
							{session ? (
								<SessionPaneTab
									isActive={target.kind === "worker"}
									label={sessionTabLabel}
									onSelect={onSelectSessionTerminal}
									session={session}
								/>
							) : (
								<SessionPaneTab isActive={target.kind === "worker"} label={sessionTabLabel} />
							)}
							{reviewerTerminal ? (
								<SessionPaneTab
									icon={<AgentAvatar provider={reviewerTerminal.harness} className="size-icon-base" decorative />}
									isActive={target.kind === "reviewer"}
									label={t("terminal.reviewer")}
									onSelect={() => onSelectReviewerTerminal?.(reviewerTerminal)}
									title={reviewerTerminal.harness}
								/>
							) : null}
							{shellTerminals.map((shell) => (
								<ShellTerminalTab
									key={shell.handleId}
									appearance="connected"
									isActive={target.kind === "shell" && target.handleId === shell.handleId}
									onClose={() => onCloseShellTerminal?.(shell.handleId)}
									onRename={onRenameShellTerminal ? (title) => onRenameShellTerminal(shell.handleId, title) : undefined}
									onSelect={() => onSelectShellTerminal?.(shell.handleId)}
									shell={shell}
								/>
							))}
						</div>
						{tabsOverflow.canScrollRight ? (
							<button
								aria-label={t("terminal.scrollTabsRight")}
								className="inline-flex size-control-sm shrink-0 items-center justify-center rounded-sm text-muted-foreground transition-colors hover:bg-interactive-hover hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-accent/50"
								onClick={() => tabsOverflow.scrollByDirection(1)}
								title={t("terminal.scrollTabsRight")}
								type="button"
							>
								<ChevronRight aria-hidden="true" className="size-icon-md" />
							</button>
						) : null}
						{!session || !isOrchestratorSession(session) ? (
							<Tooltip>
								<TooltipTrigger asChild>
									<Button
										aria-label={t("shortcut.new-shell-terminal")}
										className="ml-2 shrink-0 text-muted-foreground"
										disabled={!onNewShellTerminal}
										onClick={onNewShellTerminal}
										size="icon-sm"
										type="button"
										variant="outline"
									>
										<Plus aria-hidden="true" className="size-icon-md" />
									</Button>
								</TooltipTrigger>
								<TooltipContent>{t("terminal.newWithShortcut", { shortcut: newTerminalShortcutLabel })}</TooltipContent>
							</Tooltip>
						) : null}
					</div>
				</div>
				<div className="ml-auto flex shrink-0 items-center px-3" data-testid="session-action-region">
					{topbarActions}
				</div>
			</div>
		</div>
	);

	return (
		<div
			ref={paneRef}
			className="terminal-pane-frame flex h-full min-h-0 min-w-flex-min flex-col"
		>
			<SessionTopbarPortal>{terminalTopbar}</SessionTopbarPortal>
			<div
				aria-label={t("terminal.panelAria", { title: activeTerminalLabel })}
				className="relative min-h-0 flex-1"
				role="tabpanel"
			>
				<div
					className="h-full min-h-0"
					data-testid="terminal-interaction-surface"
					inert={(isSwitchingAgent || switchNeedsRecovery) && !switchPermissionRequired ? true : undefined}
				>
					<TerminalPane
						daemonReady={daemonReady}
						fontSize={fontSize}
						focusRequested={switchPermissionRequired && target.kind === "worker"}
						inputDisabled={agentInputDisabled && target.kind === "worker"}
						session={session}
						terminalTarget={target}
						theme={theme}
					/>
				</div>
				{(isSwitchingAgent || switchNeedsRecovery) && switchSource && switchTarget ? (
					<AgentSwitchTerminalOverlay
						permissionRequired={switchPermissionRequired}
						recoveryRequired={switchNeedsRecovery}
						source={switchSource}
						target={switchTarget}
					/>
				) : null}
			</div>
		</div>
	);
}

type AgentSwitchTerminalOverlayProps = {
	permissionRequired: boolean;
	recoveryRequired: boolean;
	source: string;
	target: string;
};

function AgentSwitchTerminalOverlay({
	permissionRequired,
	recoveryRequired,
	source,
	target,
}: AgentSwitchTerminalOverlayProps) {
	const { t } = useTranslation();
	const overlayRef = useRef<HTMLDivElement | null>(null);
	const title = recoveryRequired
		? t("switchAgent.recovery.action")
		: t("switchAgent.progressTitle", {
				source: agentLabel(source),
				target: agentLabel(target),
			});

	useEffect(() => {
		if (!permissionRequired) overlayRef.current?.focus({ preventScroll: true });
	}, [permissionRequired, recoveryRequired, source, target]);

	return (
		<div
			ref={overlayRef}
			aria-label={title}
			className={cn(
				"absolute inset-0 z-20 flex items-center justify-center",
				recoveryRequired
					? "bg-terminal/95 backdrop-blur-[3px]"
					: permissionRequired
						? "pointer-events-none bg-terminal/25"
						: "cursor-wait bg-terminal/95 backdrop-blur-[3px]",
			)}
			data-testid="agent-switch-terminal-overlay"
			tabIndex={-1}
		>
			{recoveryRequired ? (
				<div
					aria-label={title}
					className="flex max-w-md flex-col items-center gap-2 rounded-lg border border-warning/40 bg-surface/95 px-5 py-4 text-center shadow-lg"
					role="alert"
				>
					<TriangleAlert aria-hidden="true" className="size-6 text-warning" />
					<p className="font-mono text-control font-medium text-foreground">
						{t("switchAgent.recovery.title")}
					</p>
					<p className="text-caption leading-4 text-muted-foreground">
						{t("switchAgent.recovery.shortDescription")}
					</p>
				</div>
			) : (
				<div
					aria-label={title}
					aria-live="polite"
					className={cn(
						"flex flex-col items-center gap-5 px-6 text-center",
						permissionRequired && "absolute inset-x-0 top-4 gap-2",
					)}
					role="status"
				>
					<div className="flex items-center gap-5 sm:gap-7">
						<SwitchingAgentMark harness={source} />
						<div aria-hidden="true" className="flex items-center gap-2 text-accent">
							<div className="relative h-1 w-20 overflow-hidden rounded-full bg-border-strong/70 sm:w-28">
								<span className="agent-switch-transfer-pulse absolute inset-y-0 w-10 rounded-full bg-gradient-to-r from-transparent via-accent to-transparent" />
							</div>
							<ArrowRight className="size-icon-lg shrink-0" />
						</div>
						<SwitchingAgentMark harness={target} />
					</div>
					<p className="font-mono text-control font-medium text-foreground">{title}</p>
					{permissionRequired ? (
						<p className="rounded-md border border-warning/40 bg-surface/95 px-3 py-2 text-caption text-foreground shadow-lg">
							{t("switchAgent.permissionRequired")}
						</p>
					) : null}
				</div>
			)}
		</div>
	);
}

function SwitchingAgentMark({ harness }: { harness: string }) {
	return (
		<div className="flex min-w-20 flex-col items-center gap-2">
			<span className="grid size-14 place-items-center rounded-xl border border-border-strong bg-surface/90 shadow-lg shadow-black/20">
				<AgentAvatar className="size-8" decorative provider={harness} />
			</span>
			<span className="text-caption font-medium text-muted-foreground">{agentLabel(harness)}</span>
		</div>
	);
}

type SessionPaneTabProps = {
	label: string;
	isActive: boolean;
	onSelect?: () => void;
	session?: WorkspaceSession;
	icon?: ReactNode;
	title?: string;
};

// Shared tab chrome: the open tab is highlighted with the same rounded
// background as the inspector rail tabs (Summary · Reviews · Browser), and
// the full label only becomes the hover tooltip when the tab strip is
// crowded enough to truncate it.
function SessionPaneTab({ label, isActive, onSelect, session, icon, title }: SessionPaneTabProps) {
	const { t } = useTranslation();
	const { ref, isTruncated } = useTruncatedText<HTMLButtonElement>(label);
	const activity = session ? getAgentActivityView(session.activity, t) : undefined;
	const tabIcon = session ? <AgentAvatar className="size-icon-base" decorative provider={session.provider} /> : icon;
	return (
		<span
			data-terminal-role="primary"
			className={cn(
				"group relative inline-flex min-w-shell-tab-min self-stretch items-center gap-1.5 border-r border-border bg-surface px-3 text-foreground transition-colors",
				isActive
					? "bg-overlay text-foreground after:absolute after:inset-x-0 after:bottom-0 after:h-0.5 after:bg-foreground/80"
					: "text-muted-foreground hover:bg-raised hover:text-foreground",
			)}
		>
			<button
				ref={ref}
				aria-current={isActive}
				aria-label={activity ? `${label} · ${activity.label}` : label}
				aria-selected={isActive}
				className={cn(
					"inline-flex min-w-flex-min max-w-shell-tab-max items-center gap-1.5 text-control font-medium leading-none transition-colors",
					isActive ? "text-foreground" : "text-passive group-hover:text-foreground",
				)}
				onClick={onSelect}
				role="tab"
				tabIndex={isActive ? 0 : -1}
				title={title ?? (isTruncated ? label : t("terminal.sessionAria"))}
				type="button"
			>
				{tabIcon}
				<span className="truncate">{label}</span>
				{activity ? (
					<span
						aria-hidden="true"
						className="inline-flex shrink-0 self-center items-center"
						style={{ color: activity.tone }}
						title={activity.label}
					>
						<span
							className={cn("size-1.5 rounded-full", activity.breathe && "animate-status-pulse")}
							style={{ background: activity.tone }}
						/>
					</span>
				) : null}
			</button>
			{session ? <TerminalSwitchAgentButton key={session.id} session={session} /> : null}
		</span>
	);
}

export function SessionBlocksPane({ session, headerActions }: { session: WorkspaceSession | undefined; headerActions?: ReactNode }) {
	const sessionId = session?.id ?? "";
	const harness = session?.provider;
	const isChat = session?.mode === "chat";

	if (isChat) {
		return (
			<div className="flex h-full min-h-0 flex-col">
				{headerActions}
				<ChatSessionBlocksPane sessionId={sessionId} />
			</div>
		);
	}

	return (
		<TuiSessionBlocksPane harness={harness} session={session} sessionId={sessionId} />
	);
}

function TuiSessionBlocksPane({
	harness,
	session,
	sessionId,
}: {
	harness: string | undefined;
	session: WorkspaceSession | undefined;
	sessionId: string;
}) {
	const blocks = useSessionBlocks(sessionId, {
		enabled: sessionId !== "",
		harness,
		sessionEnded: session?.isTerminated === true || session?.activity?.state === "exited",
	});
	const send = useTuiSend(sessionId);
	const [rerunRequest, setRerunRequest] = useState<{ text: string; revision: number }>();
	const actionContext = useMemo<BlockActionContext>(
		() => ({ mode: "tui", capabilities: [], canSend: sessionId !== "", turnInFlight: false, rollbackableTurnIds: [] }),
		[sessionId],
	);
	const onAction = useCallback(async (_block: SessionBlock, action: BlockAction) => {
		switch (action.kind) {
			case "copy_block":
			case "copy_command":
			case "copy_output":
				await copyActionPayload(action);
				return;
			case "rerun":
				setRerunRequest((current) => ({ text: action.payload ?? "", revision: (current?.revision ?? 0) + 1 }));
				return;
			case "rewind":
				return;
		}
	}, []);

	return (
		<div className="flex h-full min-h-0 flex-col">
			<div className="min-h-0 flex-1">
				<BlocksView
					blocks={blocks.blocks}
					error={blocks.error}
					harness={harness}
					hasOlder={blocks.hasOlder}
					isLoading={blocks.isLoading}
					isLoadingOlder={blocks.isLoadingOlder}
					actionContext={actionContext}
					onAction={onAction}
					onLoadOlder={blocks.loadOlder}
					onRetry={blocks.refetch}
					sessionId={sessionId}
					supported={blocksCoverHarness(harness)}
				/>
			</div>
			{sessionId === "" ? null : <BlockComposer prefill={rerunRequest} send={send} sessionId={sessionId} />}
		</div>
	);
}

function ChatSessionBlocksPane({ sessionId }: { sessionId: string }) {
	const conversation = useConversation(sessionId);
	const commands = useConversationCommands(sessionId);
	const blocks = conversation.snapshot ? blocksFromConversation(conversation.snapshot) : [];
	const supported = conversation.unavailable === undefined;
	const send = useChatSend(commands);
	const stageAttachments = useStageAttachments(sessionId);
	const skillsQuery = useConversationSkills(sessionId, supported);
	const filePathsQuery = useWorkspaceFilePaths(sessionId, supported);
	const modelsQuery = useConversationModels(sessionId, supported);
	const configOptionsQuery = useConversationConfigOptions(sessionId, supported);
	const { t } = useTranslation();
	const [rerunRequest, setRerunRequest] = useState<{ text: string; revision: number }>();
	const [rewindTurnId, setRewindTurnId] = useState<string>();

	const activitiesById = useMemo(() => {
		const map = new Map<string, ConversationActivity>();
		if (conversation.snapshot === undefined) return map;
		for (const item of conversation.snapshot.items) {
			if (item.kind !== "activity") continue;
			if (item.activityKind === "approval" || item.activityKind === "user_input") {
				map.set(item.id, item);
			}
		}
		return map;
	}, [conversation.snapshot]);

	const handleAttach = useCallback(
		async (files: File[]) => {
			if (files.length === 0) return;
			const dataUris = await Promise.all(
				files.map(
					(file) =>
						new Promise<{ mimeType: string; data: string }>((resolve, reject) => {
							const reader = new FileReader();
							reader.onload = () => {
								const result = reader.result;
								if (typeof result !== "string") {
									reject(new Error("Could not read attachment"));
									return;
															}
								resolve({ mimeType: file.type, data: result });
							};
							reader.onerror = () => reject(new Error("Could not read attachment"));
							reader.readAsDataURL(file);
						}),
				),
			);
			await stageAttachments(dataUris);
		},
		[stageAttachments],
	);

	const canApprove =
		conversation.snapshot !== undefined && snapshotCan(conversation.snapshot, "approvals");
	const canElicit = conversation.snapshot !== undefined && snapshotCan(conversation.snapshot, "elicitation");
	const canSteerCapability =
		conversation.snapshot !== undefined && snapshotCan(conversation.snapshot, "steer");
	const activeTurnId =
		conversation.snapshot?.turns.find((t) => t.state === "running")?.id ??
		conversation.snapshot?.turns.find((t) => t.state === "queued")?.id;
	const hasInFlightTurn = activeTurnId !== undefined;
	const snapshot = conversation.snapshot;
	const rollbackableTurnIds = useMemo(
		() =>
			snapshot === undefined
				? []
				: snapshot.turns
						.filter((turn) => isRollbackableTurn(snapshot, turn.id, hasInFlightTurn))
						.map((turn) => turn.id),
		[snapshot, hasInFlightTurn],
	);
	const actionContext = useMemo<BlockActionContext>(
		() => ({
			mode: "chat",
			capabilities: snapshot?.capabilities ?? [],
			canSend: sessionId !== "",
			turnInFlight: hasInFlightTurn,
			rollbackableTurnIds,
		}),
		[hasInFlightTurn, rollbackableTurnIds, sessionId, snapshot?.capabilities],
	);

	// Decision ids are the provider's, carried on the activity. Synthesizing one
	// here would resolve an approval with an option the provider never offered.
	const renderBlockActions = useCallback(
		(block: SessionBlock) => {
			if (block.kind !== "permission" || block.status !== "blocked") return null;
			const activity = activitiesById.get(block.id);
			if (activity === undefined) return null;
			const requestId = activity.requestId;
			if (requestId === undefined || requestId === "") return null;

			if (activity.activityKind === "user_input") {
				if (!canElicit) return null;
				return (
					<ElicitationCard
						activity={activity}
						onResolve={(id, action, content) => commands.resolveInput(id, action, content)}
					/>
				);
			}

			if (!canApprove) return null;
			const decisions = activity.decisions ?? [];
			if (decisions.length === 0) {
				return (
					<p className="text-[10px] text-muted-foreground">{t("blocks.noDecisions")}</p>
				);
			}
			return decisions.map((decision, index) => (
				<Button
					aria-label={decision.label}
					data-testid={`block-decision-${decision.id}`}
					key={decision.id}
					onClick={() => commands.resolve(requestId, decision.id)}
					size="sm"
					variant={index === 0 ? "primary" : "outline"}
				>
					{decision.label}
				</Button>
			));
		},
		[activitiesById, canApprove, canElicit, commands, t],
	);

	const handleRollbackTurn = useCallback(
		(turnId: string) => {
			if (!isRollbackableTurn(conversation.snapshot, turnId, hasInFlightTurn)) return;
			void commands.rollback(turnId);
		},
		[commands, conversation.snapshot, hasInFlightTurn],
	);

	const canRollbackTurnPredicate = useCallback(
		(group: TurnGroup) => {
			return group.turnId !== undefined && isRollbackableTurn(conversation.snapshot, group.turnId, hasInFlightTurn);
		},
		[conversation.snapshot, hasInFlightTurn],
	);
	const onAction = useCallback(
		async (_block: SessionBlock, action: BlockAction) => {
			switch (action.kind) {
				case "copy_block":
				case "copy_command":
				case "copy_output":
					await copyActionPayload(action);
					return;
				case "rerun":
					setRerunRequest((current) => ({ text: action.payload ?? "", revision: (current?.revision ?? 0) + 1 }));
					return;
				case "rewind":
					if (action.turnId !== undefined && rollbackableTurnIds.includes(action.turnId)) setRewindTurnId(action.turnId);
					return;
			}
		},
		[rollbackableTurnIds],
	);
	const confirmRewind = useCallback(() => {
		if (rewindTurnId === undefined) return;
		setRewindTurnId(undefined);
		handleRollbackTurn(rewindTurnId);
	}, [handleRollbackTurn, rewindTurnId]);

	return (
		<div className="flex h-full min-h-0 flex-col">
			{snapshot?.account ? (
				<ReauthBanner account={snapshot.account} harness={snapshot.harness} />
			) : null}
			{snapshot?.threadState ? <ThreadStateBanner threadState={snapshot.threadState} /> : null}
			{snapshot === undefined ? null : (
				<McpServerBanner
					error={commands.mcpReloadError}
					onReload={
						snapshotCan(snapshot, "mcp_reload") ? () => commands.reloadMcpServers() : undefined
					}
					servers={brokenMcpServers(snapshot)}
					turnInFlight={hasInFlightTurn}
				/>
			)}
			<div className="min-h-0 flex-1">
				<BlocksView
					actionContext={actionContext}
					blocks={blocks}
					canRollbackTurn={canRollbackTurnPredicate}
					error={conversation.error}
					hasOlder={conversation.hasOlder}
					isLoading={conversation.isLoading}
					isLoadingOlder={conversation.isLoadingOlder}
					onLoadOlder={conversation.loadOlder}
					onAction={onAction}
					onRetry={conversation.refetch}
					onRollbackTurn={handleRollbackTurn}
					renderActions={renderBlockActions}
					sessionId={sessionId}
					supported={supported}
					unavailable={conversation.unavailable}
				/>
			</div>
			{snapshot === undefined ? null : (
				<TurnSettingsBar
					configOptions={configOptionsQuery.options}
					disabled={snapshot.controller.state === "stopped"}
					models={modelsQuery.models}
					onChange={(next) => commands.chooseSettings(next)}
					configPending={configOptionsQuery.pending}
					error={configOptionsQuery.error}
					onChangeConfigOption={(id, value) => configOptionsQuery.setOption(id, value)}
					reroute={snapshot.modelReroute}
					settings={snapshot.settings}
				/>
			)}
			{sessionId === "" ? null : (
				<BlockComposer
					canSteer={canSteerCapability && hasInFlightTurn}
					onAttach={handleAttach}
					onSteer={canSteerCapability ? (text) => commands.steer(text) : undefined}
					prefill={rerunRequest}
					send={send}
					sessionId={sessionId}
					suggestions={buildComposerSuggestions(
						skillsQuery.skills,
						filePathsQuery.paths,
					)}
				/>
			)}
			<Dialog open={rewindTurnId !== undefined} onOpenChange={(open) => !open && setRewindTurnId(undefined)}>
				<DialogContent>
					<DialogHeader>
						<DialogTitle>{t("blocks.rewindTitle")}</DialogTitle>
						<DialogDescription>{t("blocks.rewindBody")}</DialogDescription>
					</DialogHeader>
					<DialogFooter>
						<Button onClick={() => setRewindTurnId(undefined)} type="button" variant="ghost">
							{t("blocks.cancel")}
						</Button>
						<Button onClick={() => void confirmRewind()} type="button" variant="outline">
							{t("blocks.rewindConfirm")}
						</Button>
					</DialogFooter>
				</DialogContent>
			</Dialog>
		</div>
	);
}

function isRollbackableTurn(
	snapshot: ConversationSnapshot | undefined,
	turnId: string,
	hasInFlightTurn: boolean,
): boolean {
	if (snapshot === undefined) return false;
	if (!snapshotCan(snapshot, "rollback")) return false;
	if (hasInFlightTurn) return false;
	const turn = snapshot.turns.find((candidate) => candidate.id === turnId);
	if (turn === undefined) return false;
	if (turn.state === "running" || turn.state === "queued") return false;
	if (turn.rolledBack === true) return false;
	return turn.providerTurnId !== undefined && turn.providerTurnId !== "";
}

async function copyActionPayload(action: BlockAction): Promise<void> {
	await operatorBridge.clipboard.writeText(action.payload ?? "");
}

function useChatSend(
	commands: ReturnType<typeof useConversationCommands>,
): BlockComposerSend {
	return useCallback(
		async (input: { text: string }) => {
			await commands.send(input);
		},
		[commands],
	);
}

function buildComposerSuggestions(
	skills: ChatSkill[],
	filePaths: string[],
): { trigger: string; query: string; items: Suggestion[] } | undefined {
	if (skills.length === 0 && filePaths.length === 0) return undefined;
	return {
		trigger: "/",
		query: "",
		items: [...rankSkills(skills, ""), ...rankFiles(filePaths, "")].slice(0, MAX_SUGGESTIONS),
	};
}

function useTuiSend(sessionId: string): BlockComposerSend {
	const { t } = useTranslation();
	return useCallback(
		async (input: { text: string }) => {
			const { error: failure } = await apiClient.POST("/api/v1/sessions/{sessionId}/send", {
				params: { path: { sessionId } },
				body: { message: input.text },
			});
			if (failure) throw new Error(apiErrorMessage(failure, t("blocks.sendError")));
		},
		[sessionId, t],
	);
}
