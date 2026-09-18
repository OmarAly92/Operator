import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useId, useState } from "react";
import { useTranslation } from "react-i18next";
import { agentsQueryKey, agentsQueryOptions, refreshAgentsIfStale } from "../../hooks/useAgentsQuery";
import { preferredClaudeAccountId, useClaudeAccounts } from "../../hooks/useClaudeAccounts";
import { ClaudeAccountSelect } from "../ClaudeAccountSelect";
import { RequiredAgentField } from "../CreateProjectAgentSheet";
import { FieldDefaultHint } from "../FieldDefaultHint";
import { TaskModelPicker } from "../TaskModelPicker";

export type TicketRoleValues = { harness: string; model: string; claudeAccountId: string; extra: string };

export const emptyTicketRoleValues: TicketRoleValues = { harness: "", model: "", claudeAccountId: "", extra: "" };

export function TicketRoleFields({
	projectId,
	value,
	onChange,
	disabled = false,
}: {
	projectId: string;
	value: TicketRoleValues;
	onChange: (next: TicketRoleValues) => void;
	disabled?: boolean;
}) {
	const { t } = useTranslation();
	const queryClient = useQueryClient();
	const harnessId = useId();
	const modelId = useId();
	const accountId = useId();
	const extraId = useId();
	const agentsQuery = useQuery(agentsQueryOptions);
	useEffect(() => {
		void refreshAgentsIfStale().then((next) => {
			if (next) queryClient.setQueryData(agentsQueryKey, next);
		});
	}, [queryClient]);
	const claudeAccountsQuery = useClaudeAccounts();
	const [modelWarning, setModelWarning] = useState<string | undefined>();
	const accounts = claudeAccountsQuery.data ?? [];
	const catalog = agentsQuery.data;
	const agentLabel = catalog?.supported?.find((item) => item.id === value.harness)?.label || value.harness;
	const showAccount = value.harness === "claude-code" && accounts.length > 1;
	const set = (patch: Partial<TicketRoleValues>) => onChange({ ...value, ...patch });

	return (
		<div className="flex flex-col gap-4">
			<div className="grid gap-4 sm:grid-cols-2">
				<RequiredAgentField
					id={harnessId}
					label={t("tickets.harness")}
					placeholder={t("tickets.harness")}
					value={value.harness}
					authorized={catalog?.authorized}
					installed={catalog?.installed}
					supported={catalog?.supported}
					disabled={disabled || (agentsQuery.isFetching && catalog === undefined)}
					onChange={(harness) => set({ harness, model: "", claudeAccountId: "" })}
				/>
				<div className="flex flex-col gap-1.5">
					<label className="settings-field-label" htmlFor={modelId}>
						{t("tickets.model")}
					</label>
					<TaskModelPicker
						id={modelId}
						agentId={value.harness}
						agentLabel={agentLabel}
						projectId={projectId}
						value={value.model}
						mode=""
						onModelChange={(model) => set({ model })}
						onModeChange={(model) => set({ model })}
						onWarningChange={setModelWarning}
					/>
				</div>
			</div>
			{showAccount ? (
				<div className="flex flex-col gap-1.5">
					<label className="settings-field-label" htmlFor={accountId}>
						{t("tickets.account")}
					</label>
					<ClaudeAccountSelect
						id={accountId}
						ariaLabel={t("tickets.account")}
						value={value.claudeAccountId || preferredClaudeAccountId(accounts)}
						onChange={(claudeAccountId) => set({ claudeAccountId })}
						accounts={accounts}
					/>
				</div>
			) : null}
			<div className="flex flex-col gap-1.5">
				<label className="settings-field-label" htmlFor={extraId}>
					{t("tickets.extra")}
				</label>
				<textarea
					id={extraId}
					className="settings-field-control min-h-(--size-textarea-min) resize-y py-2.5"
					disabled={disabled}
					value={value.extra}
					onChange={(event) => set({ extra: event.target.value })}
					placeholder={t("tickets.extraPlaceholder")}
				/>
			</div>
			{modelWarning ? (
				<p className="text-caption text-warning" role="status">
					{modelWarning}
				</p>
			) : null}
			<FieldDefaultHint text={t("tickets.defaultsHint")} />
		</div>
	);
}
