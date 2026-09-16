import { useTranslation } from "react-i18next";
import { claudeAccountPlanLabel, useClaudeAccounts, type ClaudeAccount } from "../hooks/useClaudeAccounts";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "./ui/select";

export function ClaudeAccountSelect({
	id,
	value,
	onChange,
	accounts,
	triggerClassName,
	ariaLabel,
	excludeId,
}: {
	id: string;
	value: string;
	onChange: (id: string) => void;
	accounts: ClaudeAccount[];
	triggerClassName?: string;
	ariaLabel: string;
	excludeId?: string;
}) {
	const { t } = useTranslation();
	const optionLabel = (account: ClaudeAccount) =>
		t("claudeAccounts.planSuffix", { label: account.label, plan: claudeAccountPlanLabel(account, t) });
	const selected = accounts.find((account) => account.id === value);
	return (
		<Select value={value} onValueChange={onChange}>
			<SelectTrigger id={id} aria-label={ariaLabel} className={triggerClassName}>
				<SelectValue>{selected?.label}</SelectValue>
			</SelectTrigger>
			<SelectContent align="start" position="popper">
				{accounts
					.filter((account) => account.id !== excludeId)
					.map((account) => (
						<SelectItem key={account.id} value={account.id}>
							{optionLabel(account)}
						</SelectItem>
					))}
			</SelectContent>
		</Select>
	);
}

export function useClaudeAccountAgentLabel(session: { provider: string; claudeAccountId?: string }, agentName: string): string {
	const { t } = useTranslation();
	const accounts = useClaudeAccountsSafe();
	if (session.provider !== "claude-code" || !session.claudeAccountId || session.claudeAccountId === "default") return agentName;
	const account = accounts.find((entry) => entry.id === session.claudeAccountId);
	return account ? t("settings.claudeAccounts.agentWithAccount", { agent: agentName, account: account.label }) : agentName;
}

function useClaudeAccountsSafe(): ClaudeAccount[] {
	return useClaudeAccounts().data ?? [];
}
