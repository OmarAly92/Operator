import { ArrowRight, ChevronLeft, ChevronRight, TriangleAlert } from "lucide-react";
import { useEffect, useRef, useState, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { useOverflowScroll } from "../hooks/useOverflowScroll";
import {
	findActiveAgentSwitch,
	findRecoveryRequiredAgentSwitch,
	useAgentSwitches,
} from "../hooks/useAgentSwitches";
import { useSwitchAgentState } from "../hooks/useSwitchAgent";
import { useTruncatedText } from "../hooks/useTruncatedText";
import { TERMINAL_FONT_SIZE_DEFAULT, TERMINAL_FONT_SIZE_MAX, TERMINAL_FONT_SIZE_MIN } from "../lib/design-tokens";
import { getAgentActivityView } from "../lib/session-presentation";
import { agentLabel } from "../lib/agent-options";
import { isLinuxPlatform, isMacPlatform } from "../lib/platform";
import { handleTerminalTabListKeyDown } from "../lib/terminal-tabs";
import { cn } from "../lib/utils";
import { useUiStore, type Theme } from "../stores/ui-store";
import type { TerminalTarget } from "../types/terminal";
import { isOrchestratorSession, type WorkspaceSession } from "../types/workspace";
import { AgentAvatar } from "./AgentAvatar";
import { TerminalPane } from "./TerminalPane";
import { SessionTopbarPortal } from "./SessionTopbarPortal";
import { TerminalSwitchAgentButton } from "./TerminalSwitchAgentButton";

type CenterPaneProps = {
	session?: WorkspaceSession;
	theme: Theme;
	daemonReady: boolean;
	terminalTarget?: TerminalTarget;
	reviewerTerminal?: { handleId: string; harness: string };
	onSelectReviewerTerminal?: (target: { handleId: string; harness: string }) => void;
	onSelectSessionTerminal?: () => void;
	/** Session actions consolidated into the terminal bar by SessionView. */
	topbarActions?: ReactNode;
};

const terminalFontSizeStorageKey = "opr.terminal.fontSize";
const isMac = isMacPlatform();
const isLinux = isLinuxPlatform();

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
	onSelectSessionTerminal,
	topbarActions,
}: CenterPaneProps) {
	const { t } = useTranslation();
	const paneRef = useRef<HTMLDivElement | null>(null);
	const [fontSize] = useState(initialTerminalFontSize);
	const [terminalBounds, setTerminalBounds] = useState({ width: 0 });
	const isSidebarOpen = useUiStore((state) => state.isSidebarOpen);
	const tabsOverflow = useOverflowScroll<HTMLDivElement>(session?.id ?? "");
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
		target.kind === "reviewer" ? `${t("terminal.reviewer")} · ${target.harness}` : sessionTabLabel;

	useEffect(() => {
		if (!switchMutation.isPending || activeAgentSwitch || recoveryAgentSwitch) return;
		void agentSwitchesQuery.refetch();
		const timer = window.setInterval(() => void agentSwitchesQuery.refetch(), 500);
		return () => window.clearInterval(timer);
	}, [activeAgentSwitch, agentSwitchesQuery.refetch, recoveryAgentSwitch, switchMutation.isPending]);

	useEffect(() => {
		const pane = paneRef.current;
		if (!pane) return;
		// Observe the pane alone. This measurement is written back into the DOM as
		// the terminal region's width, and the topbar portal renders that region
		// inside .center-panel-surface -- so observing the surface too closed a
		// cycle: measure -> setState -> layout inside the surface -> observer ->
		// measure, spinning at frame rate for as long as the pane was mounted. The
		// surface was only ever read for leftInset/rightInset, which nothing
		// consumed, so dropping them cuts the cycle rather than damping it.
		//
		// Rounding covers what is left: getBoundingClientRect returns fractional
		// pixels, and an exact-float guard lets sub-pixel drift re-enter the
		// remaining pane -> width -> layout path. Whole pixels give it a fixed point.
		const measure = () => {
			const next = { width: Math.round(pane.getBoundingClientRect().width) };
			setTerminalBounds((current) => (current.width === next.width ? current : next));
		};
		measure();
		const observer = new ResizeObserver(measure);
		observer.observe(pane);
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
