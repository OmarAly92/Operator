import { ChevronLeft, ChevronRight } from "lucide-react";
import { Fragment, useEffect, useRef, useState, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { useOverflowScroll } from "../hooks/useOverflowScroll";
import { isLinuxPlatform, isMacPlatform, windowDragRegion } from "../lib/platform";
import { handleTerminalTabListKeyDown } from "../lib/terminal-tabs";
import { cn } from "../lib/utils";
import { useUiStore, type Theme } from "../stores/ui-store";
import type { ShellTerminal } from "../hooks/useShellTerminals";
import type { TerminalTarget } from "../types/terminal";
import type { WorkspaceSession } from "../types/workspace";
import { AgentAvatar } from "./AgentAvatar";
import { PaneTerminal } from "./split/PaneTerminal";
import { SessionPaneTab } from "./split/SessionPaneTab";
import { SessionTopbarPortal } from "./SessionTopbarPortal";
import { ShellTerminalTab } from "./ShellTerminalTab";

type CenterPaneProps = {
	session?: WorkspaceSession;
	theme: Theme;
	daemonReady: boolean;
	terminalTarget?: TerminalTarget;
	reviewerTerminal?: { handleId: string; harness: string };
	onSelectReviewerTerminal?: (target: { handleId: string; harness: string }) => void;
	onSelectSessionTerminal?: () => void;
	/** Shells opened from this session, oldest first. */
	shellTerminals?: ShellTerminal[];
	onSelectShellTerminal?: (shell: ShellTerminal) => void;
	onCloseShellTerminal?: (handleId: string) => void;
	onRenameShellTerminal?: (handleId: string, title: string) => void;
	/** Session actions consolidated into the terminal bar by SessionView. */
	topbarActions?: ReactNode;
	/** Sessions of this project open as tabs, in strip order; includes `session`. */
	sessionTabs?: WorkspaceSession[];
	onSelectSessionTab?: (sessionId: string) => void;
	onCloseSessionTab?: (sessionId: string) => void;
};

const isMac = isMacPlatform();
const isLinux = isLinuxPlatform();
const dragRegion = windowDragRegion();

export function CenterPane({
	session,
	theme,
	daemonReady,
	terminalTarget,
	reviewerTerminal,
	onSelectReviewerTerminal,
	onSelectSessionTerminal,
	shellTerminals,
	onSelectShellTerminal,
	onCloseShellTerminal,
	onRenameShellTerminal,
	topbarActions,
	sessionTabs,
	onSelectSessionTab,
	onCloseSessionTab,
}: CenterPaneProps) {
	const { t } = useTranslation();
	const paneRef = useRef<HTMLDivElement | null>(null);
	const [terminalBounds, setTerminalBounds] = useState({ width: 0 });
	const isSidebarOpen = useUiStore((state) => state.isSidebarOpen);
	const shells = shellTerminals ?? [];
	// Re-measure when a shell tab is added or removed, not only on a session
	// change: opening a shell is exactly what pushes the strip into overflow.
	const tabsOverflow = useOverflowScroll<HTMLDivElement>(
		`${(sessionTabs ?? []).map((tab) => tab.id).join(",")}|${session?.id ?? ""}|${shells.map((shell) => shell.handleId).join(",")}`,
	);
	const target = terminalTarget ?? { kind: "worker" };

	const sessionTabLabel = session ? session.title : t("terminal.noSession");
	const activeShellHandleId = target.kind === "shell" ? target.handleId : undefined;

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
		<div
			className="flex h-inspector-tabs w-full shrink-0 items-stretch bg-sidebar"
			data-tauri-drag-region={dragRegion}
		>

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
								(sessionTabs?.length ? sessionTabs : [session]).map((tabSession) =>
									tabSession.id === session.id ? (
										<Fragment key={tabSession.id}>
											<SessionPaneTab
												isActive={target.kind === "worker"}
												label={sessionTabLabel}
												onClose={onCloseSessionTab ? () => onCloseSessionTab(tabSession.id) : undefined}
												onSelect={onSelectSessionTerminal}
												session={session}
											/>
											{reviewerTerminal ? (
												<SessionPaneTab
													icon={<AgentAvatar provider={reviewerTerminal.harness} className="size-icon-base" decorative />}
													isActive={target.kind === "reviewer"}
													label={t("terminal.reviewer")}
													onSelect={() => onSelectReviewerTerminal?.(reviewerTerminal)}
													title={reviewerTerminal.harness}
												/>
											) : null}
											{/* Shells this session owns, right after the agent's own tab: the
											    connected treatment continues into the pane below, so a shell
											    reads as another surface of this session, not a separate screen. */}
											{shells.map((shell) => (
												<ShellTerminalTab
													key={shell.handleId}
													appearance="connected"
													isActive={shell.handleId === activeShellHandleId}
													onClose={() => onCloseShellTerminal?.(shell.handleId)}
													onRename={(title) => onRenameShellTerminal?.(shell.handleId, title)}
													onSelect={() => onSelectShellTerminal?.(shell)}
													shell={shell}
												/>
											))}
										</Fragment>
									) : (
										<SessionPaneTab
											key={tabSession.id}
											isActive={false}
											label={tabSession.title}
											onClose={onCloseSessionTab ? () => onCloseSessionTab(tabSession.id) : undefined}
											onSelect={() => onSelectSessionTab?.(tabSession.id)}
											session={tabSession}
										/>
									),
								)
							) : (
								<SessionPaneTab isActive={target.kind === "worker"} label={sessionTabLabel} />
							)}
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
			<PaneTerminal daemonReady={daemonReady} focused session={session} target={target} theme={theme} />
		</div>
	);
}
