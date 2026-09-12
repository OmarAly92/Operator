import { type ReactNode, useState } from "react";
import { useTranslation } from "react-i18next";
import { useRelaunchAgent, useRelaunchAgentPending } from "../hooks/useRelaunchAgent";
import { agentLabel } from "../lib/agent-options";
import type { WorkspaceSession } from "../types/workspace";
import { ConfirmDialog } from "./ConfirmDialog";
import { ContextMenu, ContextMenuContent, ContextMenuItem, ContextMenuTrigger } from "./ui/context-menu";

type SessionAgentTabMenuProps = {
	session: WorkspaceSession;
	children: ReactNode;
};

// Right-click menu on a session's own agent tab. Both actions kill the running
// agent process and bring it back on a new provider conversation, so both go
// through a confirm step. Wrapping the tab in a Radix trigger is also what
// suppresses the webview's default Back / Reload / Inspect Element menu.
//
// The reviewer tab is deliberately not wired here: it is a bare runtime handle
// with no session id, and reviewers relaunch through their own endpoints.
export function SessionAgentTabMenu({ session, children }: SessionAgentTabMenuProps) {
	const { t } = useTranslation();
	const relaunch = useRelaunchAgent();
	const isPending = useRelaunchAgentPending(session.id);
	const [confirming, setConfirming] = useState<"cleared" | "task" | null>(null);
	const [error, setError] = useState<string | null>(null);

	const disabled = Boolean(session.isTerminated) || isPending;
	const agent = agentLabel(session.provider);

	const open = (mode: "cleared" | "task") => {
		setError(null);
		setConfirming(mode);
	};

	const confirm = async () => {
		if (!confirming) return;
		try {
			await relaunch.mutateAsync({ sessionId: session.id, keepPrompt: confirming === "task" });
			setConfirming(null);
		} catch (cause) {
			setError(cause instanceof Error ? cause.message : t("terminal.relaunchFailed"));
		}
	};

	return (
		<>
			<ContextMenu>
				<ContextMenuTrigger asChild>{children}</ContextMenuTrigger>
				<ContextMenuContent className="min-w-56">
					<ContextMenuItem disabled={disabled} onSelect={() => open("cleared")}>
						{t("terminal.relaunchCleared")}
					</ContextMenuItem>
					{session.hasSavedPrompt ? (
						<ContextMenuItem disabled={disabled} onSelect={() => open("task")}>
							{t("terminal.relaunchWithTask")}
						</ContextMenuItem>
					) : null}
				</ContextMenuContent>
			</ContextMenu>
			<ConfirmDialog
				busy={relaunch.isPending}
				confirmLabel={t("terminal.relaunchConfirm")}
				description={t(
					confirming === "task" ? "terminal.relaunchWithTaskBody" : "terminal.relaunchClearedBody",
					{ agent },
				)}
				destructive
				error={error}
				onConfirm={() => void confirm()}
				onOpenChange={(next) => {
					if (next) return;
					setConfirming(null);
					setError(null);
				}}
				open={confirming !== null}
				title={t(
					confirming === "task" ? "terminal.relaunchWithTaskTitle" : "terminal.relaunchClearedTitle",
				)}
			/>
		</>
	);
}
