import { Check, ChevronDown } from "lucide-react";
import { useTranslation } from "react-i18next";
import { claudeAccountLabelForSession, useClaudeAccounts } from "../hooks/useClaudeAccounts";
import { useRelaunchConfirm } from "../hooks/useRelaunchConfirm";
import { cn } from "../lib/utils";
import type { WorkspaceSession } from "../types/workspace";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "./ui/dropdown-menu";

export function SessionClaudeAccountMenu({ session, className }: { session: WorkspaceSession; className?: string }) {
	const { t } = useTranslation();
	const accounts = useClaudeAccounts().data ?? [];
	const label = claudeAccountLabelForSession(session, accounts);
	const { request, dialog, disabled } = useRelaunchConfirm(session);
	if (!label) return null;
	const currentAccountId = session.claudeAccountId?.trim() || "default";
	return (
		<>
			<DropdownMenu>
				<DropdownMenuTrigger asChild>
					<button
						type="button"
						aria-label={t("shell.claudeAccount", { label })}
						className={cn("inline-flex max-w-44 items-center gap-1 leading-none disabled:opacity-60", className)}
						data-testid="session-claude-account"
						disabled={disabled || accounts.length === 0}
					>
						<span className="truncate">{label}</span>
						<ChevronDown aria-hidden="true" className="size-3 shrink-0 text-passive" />
					</button>
				</DropdownMenuTrigger>
				<DropdownMenuContent align="end" className="min-w-44">
					{accounts.map((account) => {
						const current = account.id === currentAccountId;
						return (
							<DropdownMenuItem disabled={current} key={account.id} onSelect={() => request({ mode: "account", account })}>
								<span className="truncate">{account.label}</span>
								{current ? <Check aria-hidden="true" className="ml-auto" /> : null}
							</DropdownMenuItem>
						);
					})}
				</DropdownMenuContent>
			</DropdownMenu>
			{dialog}
		</>
	);
}
