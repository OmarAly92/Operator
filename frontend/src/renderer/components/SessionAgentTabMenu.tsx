import { Check } from "lucide-react";
import { type ReactNode, useState } from "react";
import { useTranslation } from "react-i18next";
import { claudeAccountLabelForSession, useClaudeAccounts, type ClaudeAccount } from "../hooks/useClaudeAccounts";
import { useRelaunchAgent, useRelaunchAgentPending } from "../hooks/useRelaunchAgent";
import { agentLabel } from "../lib/agent-options";
import type { WorkspaceSession } from "../types/workspace";
import { useClaudeAccountAgentLabel } from "./ClaudeAccountSelect";
import { ConfirmDialog } from "./ConfirmDialog";
import {
	ContextMenu,
	ContextMenuContent,
	ContextMenuItem,
	ContextMenuSeparator,
	ContextMenuSub,
	ContextMenuSubContent,
	ContextMenuSubTrigger,
	ContextMenuTrigger,
} from "./ui/context-menu";

type SessionAgentTabMenuProps = {
	session: WorkspaceSession;
	children: ReactNode;
};

type PendingRelaunch = { mode: "cleared" | "task" } | { mode: "account"; account: ClaudeAccount };

// Right-click menu on a session's own agent tab. Every action kills the running
// agent process and brings it back on a new provider conversation, so each goes
// through a confirm step. Wrapping the tab in a Radix trigger is also what
// suppresses the webview's default Back / Reload / Inspect Element menu.
//
// The reviewer tab is deliberately not wired here: it is a bare runtime handle
// with no session id, and reviewers relaunch through their own endpoints.
export function SessionAgentTabMenu({ session, children }: SessionAgentTabMenuProps) {
	const { t } = useTranslation();
	const relaunch = useRelaunchAgent();
	const isPending = useRelaunchAgentPending(session.id);
	const [confirming, setConfirming] = useState<PendingRelaunch | null>(null);
	const [error, setError] = useState<string | null>(null);

	const disabled = Boolean(session.isTerminated) || isPending;
	const agent = useClaudeAccountAgentLabel(session, agentLabel(session.provider));
	const accounts = useClaudeAccounts().data ?? [];
	const isClaude = session.provider === "claude-code";
	const currentAccountId = session.claudeAccountId?.trim() || "default";
	const currentAccountLabel = claudeAccountLabelForSession(session, accounts);

	const open = (next: PendingRelaunch) => {
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

	return (
		<>
			<ContextMenu>
				<ContextMenuTrigger asChild>{children}</ContextMenuTrigger>
				<ContextMenuContent className="min-w-56">
					<ContextMenuItem disabled={disabled} onSelect={() => open({ mode: "cleared" })}>
						{t("terminal.relaunchCleared")}
					</ContextMenuItem>
					{session.hasSavedPrompt ? (
						<ContextMenuItem disabled={disabled} onSelect={() => open({ mode: "task" })}>
							{t("terminal.relaunchWithTask")}
						</ContextMenuItem>
					) : null}
					{isClaude && accounts.length > 0 ? (
						<>
							<ContextMenuSeparator />
							<ContextMenuSub>
								<ContextMenuSubTrigger disabled={disabled}>
									<span>{t("terminal.claudeAccount")}</span>
									{currentAccountLabel ? (
										<span className="ml-auto truncate pl-3 text-micro text-passive">{currentAccountLabel}</span>
									) : null}
								</ContextMenuSubTrigger>
								<ContextMenuSubContent className="min-w-44">
									{accounts.map((account) => {
										const current = account.id === currentAccountId;
										return (
											<ContextMenuItem
												disabled={current}
												key={account.id}
												onSelect={() => open({ mode: "account", account })}
											>
												<span className="truncate">{account.label}</span>
												{current ? <Check aria-hidden="true" className="ml-auto" /> : null}
											</ContextMenuItem>
										);
									})}
								</ContextMenuSubContent>
							</ContextMenuSub>
						</>
					) : null}
				</ContextMenuContent>
			</ContextMenu>
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
		</>
	);
}
