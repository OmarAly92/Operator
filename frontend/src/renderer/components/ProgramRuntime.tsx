import { useEffect, useMemo, useRef } from "react";
import { useTranslation } from "react-i18next";
import { useShellTerminals, type ShellTerminal } from "../hooks/useShellTerminals";
import { useWorkspaceQuery } from "../hooks/useWorkspaceQuery";
import { getApiBaseUrl } from "../lib/api-client";
import { operatorBridge } from "../lib/bridge";
import { useNavigateToSession } from "../lib/navigate-to-session";
import { isTerminalOnScreen } from "../lib/on-screen-terminals";
import { connectProgramFeed, programToast, programToastHandle } from "../lib/program-feed";
import { createTerminalMux, muxUrlFromApiBase, type TerminalMux } from "../lib/terminal-mux";
import { clearTerminalTitles, setTerminalTitle } from "../lib/terminal-titles";
import type { WorkspaceSummary } from "../types/workspace";

export type ProgramTarget = Readonly<{ label: string; sessionId?: string; projectId?: string }>;

export function programTargets(
	workspaces: readonly WorkspaceSummary[] | undefined,
	shells: readonly ShellTerminal[] | undefined,
): Map<string, ProgramTarget> {
	const targets = new Map<string, ProgramTarget>();
	for (const workspace of workspaces ?? []) {
		for (const session of workspace.sessions) {
			if (!session.terminalHandleId) continue;
			targets.set(session.terminalHandleId, {
				label: session.title,
				sessionId: session.id,
				projectId: session.workspaceId,
			});
		}
	}
	for (const shell of shells ?? []) {
		targets.set(shell.handleId, { label: shell.title, sessionId: shell.sessionId, projectId: shell.projectId });
	}
	return targets;
}

function defaultCreateMux(): TerminalMux {
	return createTerminalMux(muxUrlFromApiBase(getApiBaseUrl()));
}

export function ProgramRuntime({ createMux = defaultCreateMux }: { createMux?: () => TerminalMux }) {
	const { t } = useTranslation();
	const { data: workspaces } = useWorkspaceQuery();
	const { data: shells } = useShellTerminals();
	const navigateToSession = useNavigateToSession();
	const targets = useMemo(() => programTargets(workspaces, shells), [workspaces, shells]);
	const targetsRef = useRef(targets);
	targetsRef.current = targets;
	const translateRef = useRef(t);
	translateRef.current = t;
	const createMuxRef = useRef(createMux);

	useEffect(() => {
		let sequence = 0;
		return connectProgramFeed(() => createMuxRef.current(), {
			onTitle: setTerminalTitle,
			onReset: clearTerminalTitles,
			onNotification: (event) => {
				if (isTerminalOnScreen(event.handleId)) return;
				sequence += 1;
				const fallback = targetsRef.current.get(event.handleId)?.label || translateRef.current("terminal.programNotificationFallback");
				void operatorBridge.notifications.show(programToast(event, fallback, sequence)).catch((error: unknown) => {
					console.warn("Unable to show program notification", error);
				});
			},
		});
	}, []);

	useEffect(
		() =>
			operatorBridge.notifications.onClick((id) => {
				const handleId = programToastHandle(id);
				if (!handleId) return;
				const target = targetsRef.current.get(handleId);
				if (target?.sessionId) navigateToSession(target.projectId, target.sessionId);
			}),
		[navigateToSession],
	);

	return null;
}
