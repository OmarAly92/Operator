import { RadioGroup } from "radix-ui";
import { useTranslation } from "react-i18next";
import type { components } from "../../../api/schema";
import { useClaudeAccounts } from "../../hooks/useClaudeAccounts";
import { Switch } from "../ui/switch";
import { AgentModelField } from "./AgentModelField";
import { SettingsOptionMenu } from "./SettingsOptionMenu";
import { SettingsRow } from "./SettingsRow";

type TicketDefaults = components["schemas"]["TicketDefaults"];
type TicketRoleDefaults = components["schemas"]["TicketRoleDefaults"];
type AgentInfo = components["schemas"]["AgentInfo"];
type Role = "planner" | "implementer" | "reviewer";
type ReviewerMode = NonNullable<TicketDefaults["reviewerMode"]>;

const roles: readonly Role[] = ["planner", "implementer", "reviewer"];
const INHERIT = "";

function cleanRole(role: TicketRoleDefaults | undefined): TicketRoleDefaults | undefined {
	const agent = role?.agent || undefined;
	const model = role?.model?.trim() || undefined;
	const claudeAccountId = role?.claudeAccountId || undefined;
	if (!agent && !model && !claudeAccountId) return undefined;
	return {
		...(agent ? { agent } : {}),
		...(model ? { model } : {}),
		...(claudeAccountId ? { claudeAccountId } : {}),
	};
}

export function cleanTicketDefaults(value: TicketDefaults): TicketDefaults | undefined {
	const next: TicketDefaults = {};
	for (const role of roles) {
		const cleaned = cleanRole(value[role]);
		if (cleaned) next[role] = cleaned;
	}
	if (value.reviewerMode) next.reviewerMode = value.reviewerMode;
	if (value.disableAutoReview) next.disableAutoReview = true;
	return Object.keys(next).length > 0 ? next : undefined;
}

export function TicketDefaultsSection({
	value,
	onChange,
	projectId,
	fallbackAgent,
	agents,
}: {
	value: TicketDefaults;
	onChange: (next: TicketDefaults) => void;
	projectId: string;
	fallbackAgent: string;
	agents?: AgentInfo[];
}) {
	const { t } = useTranslation();
	const accounts = useClaudeAccounts().data ?? [];
	const agentOptions = [
		{ value: INHERIT, label: t("settings.project.tickets.inherit") },
		...(agents ?? []).map((agent) => ({ value: agent.id, label: agent.label || agent.id })),
	];
	const accountOptions = [
		{ value: INHERIT, label: t("settings.project.tickets.inherit") },
		...accounts.map((account) => ({ value: account.id, label: account.label })),
	];
	const roleLabels: Record<Role, string> = {
		planner: t("settings.project.tickets.planner"),
		implementer: t("settings.project.tickets.implementer"),
		reviewer: t("settings.project.tickets.reviewer"),
	};
	const setRole = (role: Role, patch: Partial<TicketRoleDefaults>) => {
		const current = value[role] ?? {};
		onChange({
			...value,
			[role]: { agent: current.agent ?? "", model: current.model ?? "", claudeAccountId: current.claudeAccountId ?? "", ...patch },
		});
	};
	const reviewerModes: Array<{ value: ReviewerMode; label: string }> = [
		{ value: "planner", label: t("settings.project.tickets.reviewerMode.planner") },
		{ value: "new", label: t("settings.project.tickets.reviewerMode.new") },
	];

	return (
		<>
			{roles.map((role) => {
				const current = value[role] ?? {};
				const effectiveAgent = current.agent || fallbackAgent;
				const showAccount = effectiveAgent === "claude-code" && accounts.length > 1;
				return (
					<div key={role} className="contents">
						<SettingsRow label={t("settings.project.tickets.agent", { role: roleLabels[role] })}>
							<SettingsOptionMenu
								aria-label={t("settings.project.tickets.agent", { role: roleLabels[role] })}
								value={current.agent ?? INHERIT}
								options={agentOptions}
								onChange={(agent) => setRole(role, { agent, model: "", claudeAccountId: "" })}
							/>
						</SettingsRow>
						<AgentModelField
							role="worker"
							agentId={effectiveAgent}
							projectId={projectId}
							model={current.model ?? ""}
							mode=""
							label={t("settings.project.tickets.model", { role: roleLabels[role] })}
							fieldId={`ticket-${role}-model`}
							onModelChange={(model) => setRole(role, { model })}
							onModeChange={() => {}}
						/>
						{showAccount ? (
							<SettingsRow label={t("settings.project.tickets.account", { role: roleLabels[role] })}>
								<SettingsOptionMenu
									aria-label={t("settings.project.tickets.account", { role: roleLabels[role] })}
									value={current.claudeAccountId ?? INHERIT}
									options={accountOptions}
									onChange={(claudeAccountId) => setRole(role, { claudeAccountId })}
								/>
							</SettingsRow>
						) : null}
					</div>
				);
			})}
			<SettingsRow label={t("settings.project.tickets.reviewerMode")}>
				<RadioGroup.Root
					aria-label={t("settings.project.tickets.reviewerMode")}
					className="settings-segment"
					value={value.reviewerMode ?? "planner"}
					onValueChange={(next) => onChange({ ...value, reviewerMode: next as ReviewerMode })}
				>
					{reviewerModes.map((option) => (
						<RadioGroup.Item key={option.value} value={option.value} className="settings-segment-item">
							{option.label}
						</RadioGroup.Item>
					))}
				</RadioGroup.Root>
			</SettingsRow>
			<SettingsRow label={t("settings.project.tickets.disableAutoReview")}>
				<Switch
					aria-label={t("settings.project.tickets.disableAutoReview")}
					checked={value.disableAutoReview ?? false}
					onCheckedChange={(disableAutoReview) => onChange({ ...value, disableAutoReview })}
				/>
			</SettingsRow>
		</>
	);
}
