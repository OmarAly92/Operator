import { ChevronLeft, ChevronRight, Plus, SquareTerminal } from "lucide-react";
import type { PointerEvent, ReactNode } from "react";
import type { TFunction } from "i18next";
import { useTranslation } from "react-i18next";
import { useOverflowScroll } from "../../hooks/useOverflowScroll";
import type { ShellTerminal } from "../../hooks/useShellTerminals";
import { handleTerminalTabListKeyDown } from "../../lib/terminal-tabs";
import { cn } from "../../lib/utils";
import { tabKey, type Pane, type TabRef } from "../../lib/split-layout";
import type { WorkspaceSession } from "../../types/workspace";
import { AgentAvatar } from "../AgentAvatar";
import { ShellTerminalTab } from "../ShellTerminalTab";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "../ui/dropdown-menu";
import { SessionPaneTab } from "./SessionPaneTab";
import { useSplitTabDraggable } from "./useSplitTabDraggable";

type PaneTabStripProps = {
	pane: Pane;
	sessions: Map<string, WorkspaceSession>;
	shells: Map<string, ShellTerminal>;
	onSelect: (tab: TabRef) => void;
	onClose: (tab: TabRef) => void;
	onRenameShell: (handleId: string, title: string) => void;
	onNewSession?: () => void;
	onNewTerminal?: () => void;
	isOpeningTerminal?: boolean;
};

function tabLabel(
	tab: TabRef,
	sessions: Map<string, WorkspaceSession>,
	shells: Map<string, ShellTerminal>,
	t: TFunction,
): string {
	if (tab.kind === "session") return sessions.get(tab.sessionId)?.title ?? t("terminal.noSession");
	if (tab.kind === "shell") return shells.get(tab.handleId)?.title ?? t("terminal.noSession");
	return t("terminal.reviewer");
}

function ScrollChevron({
	direction,
	label,
	onClick,
}: {
	direction: -1 | 1;
	label: string;
	onClick: () => void;
}) {
	return (
		<button
			aria-label={label}
			className={STRIP_BUTTON_CLASS}
			onClick={onClick}
			title={label}
			type="button"
		>
			{direction === -1 ? (
				<ChevronLeft aria-hidden="true" className="size-icon-md" />
			) : (
				<ChevronRight aria-hidden="true" className="size-icon-md" />
			)}
		</button>
	);
}

const STRIP_BUTTON_CLASS =
	"inline-flex size-control-sm shrink-0 items-center justify-center rounded-sm text-muted-foreground transition-colors hover:bg-interactive-hover hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-accent/50";

function NewTabMenu({
	onNewSession,
	onNewTerminal,
	isOpeningTerminal,
}: {
	onNewSession: () => void;
	onNewTerminal: () => void;
	isOpeningTerminal: boolean;
}) {
	const { t } = useTranslation();
	return (
		<DropdownMenu>
			<DropdownMenuTrigger asChild>
				<button aria-label={t("split.newTab")} className={cn(STRIP_BUTTON_CLASS, "mx-1")} title={t("split.newTab")} type="button">
					<Plus aria-hidden="true" className="size-icon-md" />
				</button>
			</DropdownMenuTrigger>
			<DropdownMenuContent align="start" className="min-w-44">
				<DropdownMenuItem onSelect={onNewSession}>
					<Plus aria-hidden="true" />
					{t("shell.newSession")}
				</DropdownMenuItem>
				<DropdownMenuItem disabled={isOpeningTerminal} onSelect={onNewTerminal}>
					<SquareTerminal aria-hidden="true" />
					{t("shell.openSessionTerminalAction")}
				</DropdownMenuItem>
			</DropdownMenuContent>
		</DropdownMenu>
	);
}

function DraggableTab({ tab, label, children }: { tab: TabRef; label: string; children: ReactNode }) {
	const { setNodeRef, listeners, isDragging } = useSplitTabDraggable(tab, label, "strip");
	const onPointerDown = (event: PointerEvent<HTMLDivElement>) => {
		if (event.target instanceof HTMLElement && event.target.closest("input, textarea")) return;
		listeners?.onPointerDown?.(event);
	};
	return (
		<div
			ref={setNodeRef}
			className={cn("flex self-stretch", isDragging && "opacity-50")}
			data-split-tab=""
			onPointerDown={onPointerDown}
		>
			{children}
		</div>
	);
}

export function PaneTabStrip({
	pane,
	sessions,
	shells,
	onSelect,
	onClose,
	onRenameShell,
	onNewSession,
	onNewTerminal,
	isOpeningTerminal = false,
}: PaneTabStripProps) {
	const { t } = useTranslation();
	const overflow = useOverflowScroll<HTMLDivElement>(pane.tabs.map(tabKey).join(","));

	function renderTab(tab: TabRef, isActive: boolean) {
		if (tab.kind === "session") {
			const session = sessions.get(tab.sessionId);
			return (
				<SessionPaneTab
					isActive={isActive}
					label={session?.title ?? t("terminal.noSession")}
					onClose={() => onClose(tab)}
					onSelect={() => onSelect(tab)}
					session={session}
				/>
			);
		}
		if (tab.kind === "shell") {
			const shell = shells.get(tab.handleId);
			if (!shell) return null;
			return (
				<ShellTerminalTab
					appearance="connected"
					isActive={isActive}
					onClose={() => onClose(tab)}
					onRename={(title) => onRenameShell(tab.handleId, title)}
					onSelect={() => onSelect(tab)}
					shell={shell}
				/>
			);
		}
		return (
			<SessionPaneTab
				icon={<AgentAvatar className="size-icon-base" decorative provider={tab.harness} />}
				isActive={isActive}
				label={t("terminal.reviewer")}
				onClose={() => onClose(tab)}
				onSelect={() => onSelect(tab)}
				title={tab.harness}
			/>
		);
	}

	return (
		<div className="flex h-full min-w-flex-min flex-1 items-center">
			{overflow.canScrollLeft ? (
				<ScrollChevron direction={-1} label={t("terminal.scrollTabsLeft")} onClick={() => overflow.scrollByDirection(-1)} />
			) : null}
			<div
				ref={overflow.ref}
				aria-label={t("terminal.tabsAria")}
				className="scrollbar-none flex min-w-flex-min shrink self-stretch items-center overflow-x-auto"
				onKeyDown={handleTerminalTabListKeyDown}
				role="tablist"
			>
				{pane.tabs.map((tab, index) => (
					<DraggableTab key={tabKey(tab)} label={tabLabel(tab, sessions, shells, t)} tab={tab}>
						{renderTab(tab, index === pane.activeTab)}
					</DraggableTab>
				))}
			</div>
			{overflow.canScrollRight ? (
				<ScrollChevron direction={1} label={t("terminal.scrollTabsRight")} onClick={() => overflow.scrollByDirection(1)} />
			) : null}
			{onNewSession && onNewTerminal ? (
				<NewTabMenu isOpeningTerminal={isOpeningTerminal} onNewSession={onNewSession} onNewTerminal={onNewTerminal} />
			) : null}
		</div>
	);
}
