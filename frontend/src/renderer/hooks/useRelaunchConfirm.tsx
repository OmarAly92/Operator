import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useClaudeAccountAgentLabel } from "../components/ClaudeAccountSelect";
import { ConfirmDialog } from "../components/ConfirmDialog";
import { agentLabel } from "../lib/agent-options";
import type { WorkspaceSession } from "../types/workspace";
import type { ClaudeAccount } from "./useClaudeAccounts";
import { useRelaunchAgent, useRelaunchAgentPending } from "./useRelaunchAgent";

export type PendingRelaunch = { mode: "cleared" | "task" } | { mode: "account"; account: ClaudeAccount };

export function useRelaunchConfirm(session: WorkspaceSession) {
	const { t } = useTranslation();
	const relaunch = useRelaunchAgent();
	const isPending = useRelaunchAgentPending(session.id);
	const [confirming, setConfirming] = useState<PendingRelaunch | null>(null);
	const [error, setError] = useState<string | null>(null);
	const agent = useClaudeAccountAgentLabel(session, agentLabel(session.provider));

	const request = (next: PendingRelaunch) => {
		setError(null);
		setConfirming(next);
	};

	const confirm = async () => {
		if (!confirming) return;
		try {
			await relaunch.mutateAsync({
				sessionId: session.id,
				keepPrompt: confirming.mode === "task",
				...(confirming.mode === "account" ? { claudeAccountId: confirming.account.id } : {}),
			});
			setConfirming(null);
		} catch (cause) {
			setError(cause instanceof Error ? cause.message : t("terminal.relaunchFailed"));
		}
	};

	const title =
		confirming?.mode === "account"
			? t("terminal.switchAccountTitle", { account: confirming.account.label })
			: confirming?.mode === "task"
				? t("terminal.relaunchWithTaskTitle")
				: t("terminal.relaunchClearedTitle");
	const description =
		confirming?.mode === "account"
			? t("terminal.switchAccountBody", { agent, account: confirming.account.label })
			: confirming?.mode === "task"
				? t("terminal.relaunchWithTaskBody", { agent })
				: t("terminal.relaunchClearedBody", { agent });

	const dialog = (
		<ConfirmDialog
			busy={relaunch.isPending}
			confirmLabel={t("terminal.relaunchConfirm")}
			description={description}
			destructive
			error={error}
			onConfirm={() => void confirm()}
			onOpenChange={(next) => {
				if (next) return;
				setConfirming(null);
				setError(null);
			}}
			open={confirming !== null}
			title={title}
		/>
	);

	return { request, dialog, disabled: Boolean(session.isTerminated) || isPending };
}
