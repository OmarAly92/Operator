import { useEffect, useMemo, useRef } from "react";
import { useShellTerminals } from "../../hooks/useShellTerminals";
import { useSessionReviewer } from "../../hooks/useSessionReviewer";
import { listPanes, type TabRef } from "../../lib/split-layout";
import { useSplitLayoutStore } from "../../stores/split-layout-store";
import { useUiStore } from "../../stores/ui-store";
import type { WorkspaceSession } from "../../types/workspace";

export function SessionCompanions({ session }: { session: WorkspaceSession }) {
	const shellsQuery = useShellTerminals();
	const { reviewer, settled: reviewerSettled } = useSessionReviewer(session);
	const insertTabAfter = useSplitLayoutStore((state) => state.insertTabAfter);
	const closeTab = useSplitLayoutStore((state) => state.closeTab);
	const focusTab = useSplitLayoutStore((state) => state.focusTab);
	const reviewerDismissed = useSplitLayoutStore((state) =>
		reviewer ? state.dismissedReviewers.includes(reviewer.handleId) : false,
	);
	const requestedShell = useUiStore((state) => state.activeShellTerminalHandleId);
	const appliedShellRef = useRef<string | null>(null);
	const anchor = useMemo<TabRef>(() => ({ kind: "session", sessionId: session.id }), [session.id]);
	const reviewerHandleId = reviewer?.handleId;
	const reviewerHarness = reviewer?.harness;

	useEffect(() => {
		for (const shell of shellsQuery.data ?? []) {
			if (shell.sessionId !== session.id) continue;
			insertTabAfter({ kind: "shell", handleId: shell.handleId, sessionId: session.id }, anchor);
		}
	}, [anchor, insertTabAfter, session.id, shellsQuery.data]);

	useEffect(() => {
		if (!reviewerSettled) return;
		const { layout } = useSplitLayoutStore.getState();
		for (const pane of listPanes(layout.root)) {
			for (const tab of pane.tabs) {
				if (tab.kind === "reviewer" && tab.sessionId === session.id && tab.handleId !== reviewerHandleId) closeTab(tab);
			}
		}
		if (reviewerHandleId && reviewerHarness && !reviewerDismissed) {
			insertTabAfter({ kind: "reviewer", sessionId: session.id, handleId: reviewerHandleId, harness: reviewerHarness }, anchor);
		}
	}, [anchor, closeTab, insertTabAfter, reviewerDismissed, reviewerHandleId, reviewerHarness, reviewerSettled, session.id]);

	useEffect(() => {
		if (!requestedShell || appliedShellRef.current === requestedShell) return;
		const shell = (shellsQuery.data ?? []).find((candidate) => candidate.handleId === requestedShell);
		if (!shell || shell.sessionId !== session.id) return;
		appliedShellRef.current = requestedShell;
		focusTab({ kind: "shell", handleId: shell.handleId, sessionId: session.id });
	}, [focusTab, requestedShell, session.id, shellsQuery.data]);

	return null;
}
