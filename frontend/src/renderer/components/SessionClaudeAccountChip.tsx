import { useTranslation } from "react-i18next";
import { claudeAccountLabelForSession, useClaudeAccounts } from "../hooks/useClaudeAccounts";
import { cn } from "../lib/utils";
import type { WorkspaceSession } from "../types/workspace";

export function SessionClaudeAccountChip({
	session,
	className,
}: {
	session: Pick<WorkspaceSession, "provider" | "claudeAccountId">;
	className?: string;
}) {
	const { t } = useTranslation();
	const accounts = useClaudeAccounts().data;
	const label = claudeAccountLabelForSession(session, accounts);
	if (!label) return null;
	return (
		<span
			className={cn("inline-flex max-w-40 items-center leading-none", className)}
			data-testid="session-claude-account"
			title={t("shell.claudeAccount", { label })}
		>
			<span className="truncate">{label}</span>
		</span>
	);
}
