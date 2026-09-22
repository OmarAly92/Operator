import { Check } from "lucide-react";
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { claudeAccountLabelForSession, useClaudeAccounts } from "../hooks/useClaudeAccounts";
import { useRelaunchConfirm } from "../hooks/useRelaunchConfirm";
import { useSwitchAgentAction } from "../hooks/useSwitchAgentAction";
import type { WorkspaceSession } from "../types/workspace";
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

// Right-click menu on a session's own agent tab. Every action kills the running
// agent process and brings it back on a new provider conversation, so each goes
// through a confirm step. Wrapping the tab in a Radix trigger is also what
// suppresses the webview's default Back / Reload / Inspect Element menu.
//
// The reviewer tab is deliberately not wired here: it is a bare runtime handle
// with no session id, and reviewers relaunch through their own endpoints.
export function SessionAgentTabMenu({ session, children }: SessionAgentTabMenuProps) {
	const { t } = useTranslation();
	const { request: open, dialog, disabled } = useRelaunchConfirm(session);
	const accounts = useClaudeAccounts().data ?? [];
	const isClaude = session.provider === "claude-code";
	const currentAccountId = session.claudeAccountId?.trim() || "default";
	const currentAccountLabel = claudeAccountLabelForSession(session, accounts);
	const switchAgent = useSwitchAgentAction(session);

	return (
		<>
			<ContextMenu>
				<ContextMenuTrigger asChild>{children}</ContextMenuTrigger>
				<ContextMenuContent className="min-w-56">
					{switchAgent.available ? (
						<>
							<ContextMenuItem
								className={switchAgent.recovery ? "text-warning" : undefined}
								onSelect={switchAgent.open}
							>
								{switchAgent.label}
							</ContextMenuItem>
							<ContextMenuSeparator />
						</>
					) : null}
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
			{dialog}
			{switchAgent.dialog}
		</>
	);
}
