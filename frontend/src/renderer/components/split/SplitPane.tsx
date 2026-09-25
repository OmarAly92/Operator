import { PanelRightClose, PanelRightOpen, X } from "lucide-react";
import { useTranslation } from "react-i18next";
import { activeTabOf, tabSessionId, type Pane, type TabRef } from "../../lib/split-layout";
import { isLinuxPlatform, isMacPlatform, windowDragRegion } from "../../lib/platform";
import { cn } from "../../lib/utils";
import { inspectorState, useUiStore, type Theme } from "../../stores/ui-store";
import type { ShellTerminal } from "../../hooks/useShellTerminals";
import type { WorkspaceSession } from "../../types/workspace";
import { SessionClaudeAccountMenu } from "../SessionClaudeAccountMenu";
import { TopbarButton } from "../TopbarButton";
import { PaneTabStrip } from "./PaneTabStrip";
import { PaneTerminal, terminalTargetForTab } from "./PaneTerminal";
import { registerPaneElement } from "./pane-registry";
import { useTerminalTitle } from "../../lib/terminal-titles";

const isMac = isMacPlatform();
const isLinux = isLinuxPlatform();
const dragRegion = windowDragRegion();

type SplitPaneProps = {
	pane: Pane;
	focused: boolean;
	showFocusRing: boolean;
	touchesTop: boolean;
	topLeft: boolean;
	sessions: Map<string, WorkspaceSession>;
	shells: Map<string, ShellTerminal>;
	theme: Theme;
	daemonReady: boolean;
	onFocus: () => void;
	onSelect: (tab: TabRef) => void;
	onClose: (tab: TabRef) => void;
	onClosePane: () => void;
	onRenameShell: (handleId: string, title: string) => void;
	onNewSession?: () => void;
	onNewTerminal?: () => void;
	isOpeningTerminal?: boolean;
};

function PaneSessionActions({ session, onFocus }: { session: WorkspaceSession; onFocus: () => void }) {
	const { t } = useTranslation();
	const isInspectorOpen = useUiStore((state) => inspectorState(state.inspectorSessions, session.id).isOpen);
	const toggleInspector = useUiStore((state) => state.toggleInspector);
	const handleToggleInspector = () => {
		onFocus();
		toggleInspector(session.id);
	};
	return (
		<>
			<SessionClaudeAccountMenu
				className="h-control-sm rounded-md border border-border bg-surface px-2 text-micro font-semibold tracking-wide-sm text-muted-foreground hover:text-foreground"
				session={session}
			/>
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
	);
}

export function SplitPane(props: SplitPaneProps) {
	const { t } = useTranslation();
	const isSidebarOpen = useUiStore((state) => state.isSidebarOpen);
	const tab = activeTabOf(props.pane);
	const sessionId = tabSessionId(tab);
	const session = sessionId ? props.sessions.get(sessionId) : undefined;
	const shell = tab.kind === "shell" ? props.shells.get(tab.handleId) : undefined;
	const paneTitle = useTerminalTitle(tab.kind === "session" ? session?.terminalHandleId : tab.handleId);
	return (
		<section
			ref={(element) => registerPaneElement(props.pane.id, "pane", element)}
			className="relative flex h-full min-h-0 min-w-0 flex-col bg-background"
			data-split-pane={props.pane.id}
			onFocusCapture={props.onFocus}
			onPointerDownCapture={props.onFocus}
		>
			<header
				ref={(element) => registerPaneElement(props.pane.id, "strip", element)}
				className={cn(
					"flex h-inspector-tabs w-full shrink-0 items-stretch bg-sidebar",
					props.topLeft && !isSidebarOpen && isMac && "session-topbar-titlebar-clearance-mac",
					props.topLeft && !isSidebarOpen && isLinux && "session-topbar-titlebar-clearance-linux",
				)}
				data-tauri-drag-region={props.touchesTop ? dragRegion : undefined}
			>
				<PaneTabStrip
					isOpeningTerminal={props.isOpeningTerminal}
					onClose={props.onClose}
					onNewSession={props.onNewSession}
					onNewTerminal={props.onNewTerminal}
					onRenameShell={props.onRenameShell}
					onSelect={props.onSelect}
					pane={props.pane}
					sessions={props.sessions}
					shells={props.shells}
				/>
				{paneTitle ? (
					<span
						aria-label={t("terminal.programTitleAria", { title: paneTitle })}
						className="min-w-0 max-w-[40%] shrink truncate self-center pl-3 text-micro text-muted-foreground"
						data-testid="pane-terminal-title"
						title={paneTitle}
					>
						{paneTitle}
					</span>
				) : null}
				<div className="ml-auto flex shrink-0 items-center gap-1.5 px-3">
					{session ? <PaneSessionActions session={session} onFocus={props.onFocus} /> : null}
					<TopbarButton
						aria-label={t("split.closePane")}
						onClick={props.onClosePane}
						title={t("split.closePane")}
						variant="icon"
					>
						<X aria-hidden="true" className="size-icon-md" />
					</TopbarButton>
				</div>
			</header>
			<PaneTerminal
				daemonReady={props.daemonReady}
				focused={props.focused}
				session={session}
				target={terminalTargetForTab(tab, shell)}
				theme={props.theme}
			/>
			{props.showFocusRing ? (
				<div aria-hidden="true" className="pointer-events-none absolute inset-0 z-10 rounded-lg border border-ring/60" />
			) : null}
		</section>
	);
}
