import { useState } from "react";
import { useTranslation } from "react-i18next";
import { ticketErrorMessage, useTicketMutations } from "../../hooks/useTicketMutations";
import type { PlanView, TicketView } from "../../lib/ticket-presentation";
import { ConfirmDialog } from "../ConfirmDialog";
import { MarkdownBody } from "../MarkdownBody";

export function MergeConfirmDialog({
	open,
	onOpenChange,
	ticket,
	plan,
}: {
	open: boolean;
	onOpenChange: (open: boolean) => void;
	ticket: Pick<TicketView, "projectId" | "slug">;
	plan: Pick<PlanView, "file" | "title" | "mergeSummary">;
}) {
	const { t } = useTranslation();
	const { approveMerge } = useTicketMutations();
	const [error, setError] = useState<string | null>(null);
	const confirm = async () => {
		setError(null);
		try {
			await approveMerge.mutateAsync({ projectId: ticket.projectId, slug: ticket.slug, plan: plan.file });
			onOpenChange(false);
		} catch (err) {
			setError(ticketErrorMessage(err, t, "tickets.mergeFailed"));
		}
	};
	return (
		<ConfirmDialog
			open={open}
			title={t("tickets.mergeTitle", { plan: plan.title })}
			description={
				<div className="flex flex-col gap-2">
					<span>{t("tickets.mergeDescription")}</span>
					{plan.mergeSummary ? <MarkdownBody body={plan.mergeSummary} testId="merge-summary" /> : null}
				</div>
			}
			confirmLabel={approveMerge.isPending ? t("tickets.merging") : t("tickets.merge")}
			busy={approveMerge.isPending}
			error={error}
			onConfirm={() => void confirm()}
			onOpenChange={(next) => {
				if (!next) setError(null);
				onOpenChange(next);
			}}
		/>
	);
}
