import { Fragment, useCallback, useEffect, useMemo, type ReactNode } from "react";
import { useNavigate } from "@tanstack/react-router";
import {
	activeTabOf,
	focusedPane,
	isTopLeftPane,
	listPanes,
	paneTouchesTop,
	tabSessionId,
	type LayoutNode,
	type Pane,
	type TabRef,
} from "../../lib/split-layout";
import { MIN_PANE_HEIGHT, MIN_PANE_WIDTH } from "../../lib/split-drop";
import { useSplitLayoutStore } from "../../stores/split-layout-store";
import { useShellTerminals, useCloseShellTerminal, useRenameShellTerminal } from "../../hooks/useShellTerminals";
import { useWorkspaceQuery } from "../../hooks/useWorkspaceQuery";
import { operatorBridge } from "../../lib/bridge";
import { useShell } from "../../lib/shell-context";
import { useResolvedTheme, useUiStore } from "../../stores/ui-store";
import type { TerminalTarget } from "../../types/terminal";
import { ResizableHandle, ResizablePanel, ResizablePanelGroup } from "../ui/resizable";
import { SessionCompanions } from "./SessionCompanions";
import { SplitPane } from "./SplitPane";

export function SplitWorkspace({ routeSessionId }: { routeSessionId: string }) {
	const navigate = useNavigate();
	const theme = useResolvedTheme();
	const { daemonStatus } = useShell();
	const workspaceQuery = useWorkspaceQuery();
	const shellsQuery = useShellTerminals();
	const closeShellTerminal = useCloseShellTerminal();
	const renameShellTerminal = useRenameShellTerminal();
	const layout = useSplitLayoutStore((state) => state.layout);
	const store = useSplitLayoutStore.getState;
	const setVisibleTerminalKind = useUiStore((state) => state.setVisibleTerminalKind);
	const clearVisibleTerminalKind = useUiStore((state) => state.clearVisibleTerminalKind);

	const sessions = useMemo(
		() => new Map((workspaceQuery.data ?? []).flatMap((workspace) => workspace.sessions.map((session) => [session.id, session] as const))),
		[workspaceQuery.data],
	);
	const shells = useMemo(
		() => new Map((shellsQuery.data ?? []).map((shell) => [shell.handleId, shell] as const)),
		[shellsQuery.data],
	);
	const panes = listPanes(layout.root);
	const focused = focusedPane(layout);
	const focusedSessionId = focused ? tabSessionId(activeTabOf(focused)) : undefined;

	useEffect(() => {
		const current = focusedPane(store().layout);
		if (current && tabSessionId(activeTabOf(current)) === routeSessionId) return;
		store().openTab({ kind: "session", sessionId: routeSessionId });
	}, [routeSessionId, store]);

	useEffect(() => {
		const current = focusedPane(store().layout);
		const sessionId = current ? tabSessionId(activeTabOf(current)) : undefined;
		if (!sessionId || sessionId === routeSessionId) return;
		const session = sessions.get(sessionId);
		if (!session) return;
		void navigate({ to: "/projects/$projectId/sessions/$sessionId", params: { projectId: session.workspaceId, sessionId } });
	}, [focusedSessionId, navigate, routeSessionId, sessions, store]);

	useEffect(() => {
		if (!workspaceQuery.isSuccess || !shellsQuery.isSuccess) return;
		store().pruneTabs((tab) => (tab.kind === "shell" ? shells.has(tab.handleId) : sessions.has(tab.sessionId)));
	}, [sessions, shells, shellsQuery.isSuccess, store, workspaceQuery.isSuccess]);

	useEffect(() => {
		const kinds = new Map<string, TerminalTarget["kind"]>();
		for (const pane of listPanes(layout.root)) {
			const tab = activeTabOf(pane);
			const sessionId = tabSessionId(tab);
			if (!sessionId || kinds.get(sessionId) === "worker") continue;
			kinds.set(sessionId, tab.kind === "session" ? "worker" : tab.kind);
		}
		for (const [sessionId, kind] of kinds) setVisibleTerminalKind(sessionId, kind);
		return () => {
			for (const sessionId of kinds.keys()) clearVisibleTerminalKind(sessionId);
		};
	}, [clearVisibleTerminalKind, layout, setVisibleTerminalKind]);

	const leaveIfEmpty = useCallback(
		(projectId: string | undefined) => {
			if (store().layout.root || !projectId) return;
			void navigate({ to: "/projects/$projectId", params: { projectId }, replace: true });
		},
		[navigate, store],
	);

	const closeTab = useCallback(
		(tab: TabRef) => {
			const sessionId = tabSessionId(tab);
			const projectId = sessionId ? sessions.get(sessionId)?.workspaceId : undefined;
			if (tab.kind === "shell") closeShellTerminal.mutate(tab.handleId);
			store().closeTab(tab);
			leaveIfEmpty(projectId);
		},
		[closeShellTerminal, leaveIfEmpty, sessions, store],
	);

	const closePane = useCallback(
		(pane: Pane) => {
			const sessionId = tabSessionId(activeTabOf(pane));
			const projectId = sessionId ? sessions.get(sessionId)?.workspaceId : undefined;
			store().closePane(pane.id);
			leaveIfEmpty(projectId);
		},
		[leaveIfEmpty, sessions, store],
	);

	useEffect(
		() =>
			operatorBridge.app.onCloseShellTerminalShortcut(() => {
				const current = focusedPane(store().layout);
				if (current) closeTab(activeTabOf(current));
			}),
		[closeTab, store],
	);

	useEffect(() => {
		operatorBridge.app.setCloseShellTerminalShortcutEnabled(true);
		return () => operatorBridge.app.setCloseShellTerminalShortcutEnabled(false);
	}, []);

	useEffect(() => {
		const disposePrevious = operatorBridge.app.onPreviousTabShortcut(() => store().cycleTab(-1));
		const disposeNext = operatorBridge.app.onNextTabShortcut(() => store().cycleTab(1));
		return () => {
			disposePrevious();
			disposeNext();
		};
	}, [store]);

	const sessionTabs = [...new Set(panes.flatMap((pane) => pane.tabs).filter((tab) => tab.kind === "session").map((tab) => tab.sessionId))];

	const renderNode = (node: LayoutNode): ReactNode => {
		if (node.type === "pane") {
			return (
				<SplitPane
					daemonReady={daemonStatus.state === "ready"}
					focused={node.id === layout.focusedPaneId}
					onClose={closeTab}
					onClosePane={() => closePane(node)}
					onFocus={() => store().focusPane(node.id)}
					onRenameShell={(handleId, title) => renameShellTerminal.mutate({ handleId, title })}
					onSelect={(tab) => store().focusTab(tab)}
					pane={node}
					sessions={sessions}
					shells={shells}
					showFocusRing={panes.length > 1 && node.id === layout.focusedPaneId}
					theme={theme}
					topLeft={isTopLeftPane(layout, node.id)}
					touchesTop={paneTouchesTop(layout, node.id)}
				/>
			);
		}
		const minSize = node.direction === "row" ? MIN_PANE_WIDTH : MIN_PANE_HEIGHT;
		return (
			<ResizablePanelGroup
				id={node.id}
				key={`${node.id}:${node.children.map((child) => child.id).join(",")}`}
				onLayoutChanged={(sizes) => store().resizeSplit(node.id, node.children.map((child) => sizes[child.id] ?? 0))}
				orientation={node.direction === "row" ? "horizontal" : "vertical"}
			>
				{node.children.map((child, index) => (
					<Fragment key={child.id}>
						{index > 0 ? <ResizableHandle /> : null}
						<ResizablePanel defaultSize={`${node.sizes[index]}%`} id={child.id} minSize={minSize} style={{ overflow: "hidden" }}>
							{renderNode(child)}
						</ResizablePanel>
					</Fragment>
				))}
			</ResizablePanelGroup>
		);
	};

	return (
		<div className="relative h-full min-h-0" data-testid="split-workspace">
			{sessionTabs.map((sessionId) => {
				const session = sessions.get(sessionId);
				return session ? <SessionCompanions key={sessionId} session={session} /> : null;
			})}
			{layout.root ? renderNode(layout.root) : null}
		</div>
	);
}
