import { useQueryClient } from "@tanstack/react-query";
import { useNavigate } from "@tanstack/react-router";
import { X } from "lucide-react";
import { useEffect, useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { assignBlockedWarnings, ticketErrorMessage, useTicketMutations } from "../../hooks/useTicketMutations";
import { fetchTicket, ticketQueryKey } from "../../hooks/useTicketsQuery";
import { assignWarningLabel, needsForce, planBranchName } from "../../lib/ticket-assign";
import { planNumber, type PlanView, type TicketWithProject } from "../../lib/ticket-presentation";
import { Button } from "../ui/button";
import {
	Dialog,
	DialogClose,
	DialogContent,
	DialogDescription,
	DialogTitle,
	settingsDialogBodyClass,
	settingsDialogContentClass,
	settingsDialogFooterClass,
	settingsDialogHeaderClass,
} from "../ui/dialog";
import { emptyTicketRoleValues, TicketRoleFields, type TicketRoleValues } from "./TicketRoleFields";

export function AssignPlanSheet({
	open,
	onOpenChange,
	ticket,
	plan,
}: {
	open: boolean;
	onOpenChange: (open: boolean) => void;
	ticket: Pick<TicketWithProject, "projectId" | "slug" | "title" | "projectName">;
	plan: Pick<PlanView, "file" | "title" | "status" | "sessionId">;
}) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const queryClient = useQueryClient();
	const { assignPlan } = useTicketMutations();
	const assign = assignPlan.mutateAsync;
	const [values, setValues] = useState<TicketRoleValues>(emptyTicketRoleValues);
	const [warnings, setWarnings] = useState<string[] | null>(null);
	const [error, setError] = useState<string | null>(null);
	const [busy, setBusy] = useState(false);
	const checking = warnings === null;
	const terminating = warnings?.includes("plan_assigned") ?? false;

	useEffect(() => {
		if (!open) {
			setValues(emptyTicketRoleValues);
			setWarnings(null);
			setError(null);
			setBusy(false);
			return;
		}
		let cancelled = false;
		setWarnings(null);
		setError(null);
		assign({ projectId: ticket.projectId, slug: ticket.slug, plan: plan.file, dryRun: true })
			.then((result) => {
				if (!cancelled) setWarnings(result.warnings);
			})
			.catch((err: unknown) => {
				if (cancelled) return;
				setWarnings([]);
				setError(ticketErrorMessage(err, t, "tickets.assignFailed"));
			});
		return () => {
			cancelled = true;
		};
	}, [assign, open, plan.file, t, ticket.projectId, ticket.slug]);

	const resolveTerminateSessionId = async (): Promise<string | undefined> => {
		try {
			const fresh = await queryClient.fetchQuery({
				queryKey: ticketQueryKey(ticket.projectId, ticket.slug),
				queryFn: () => fetchTicket(ticket.projectId, ticket.slug),
			});
			const freshPlan = fresh.plans.find((candidate) => candidate.file === plan.file);
			return freshPlan?.sessionId ?? plan.sessionId;
		} catch {
			return plan.sessionId;
		}
	};

	const submit = async (event: FormEvent<HTMLFormElement>) => {
		event.preventDefault();
		if (busy || warnings === null) return;
		setBusy(true);
		setError(null);
		try {
			const terminateSessionId = terminating ? await resolveTerminateSessionId() : undefined;
			const result = await assign({
				projectId: ticket.projectId,
				slug: ticket.slug,
				plan: plan.file,
				...values,
				force: needsForce(warnings) || undefined,
				terminateSessionId,
			});
			onOpenChange(false);
			if (result.session) {
				void navigate({
					to: "/projects/$projectId/sessions/$sessionId",
					params: { projectId: result.session.projectId || ticket.projectId, sessionId: result.session.id },
				});
			}
		} catch (err) {
			const blocked = assignBlockedWarnings(err);
			if (blocked.length > 0) setWarnings(blocked);
			setError(ticketErrorMessage(err, t, "tickets.assignFailed"));
		} finally {
			setBusy(false);
		}
	};

	const number = planNumber(plan.file);
	const rows: Array<[string, string]> = [
		[t("tickets.assignTicket"), ticket.title],
		[t("tickets.assignPlan"), number ? `${number} ${plan.title}` : plan.title],
		[t("tickets.project"), ticket.projectName],
		[t("tickets.assignBranch"), planBranchName(ticket.slug, plan.file)],
	];

	return (
		<Dialog open={open} onOpenChange={(next) => !busy && onOpenChange(next)}>
			<DialogContent showCloseButton={false} className={settingsDialogContentClass}>
				<DialogClose asChild>
					<button
						type="button"
						disabled={busy}
						className="settings-dialog-close-button settings-close-button"
						aria-label={t("confirm.close")}
						title={t("confirm.closeEsc")}
					>
						<X className="size-5" aria-hidden="true" />
					</button>
				</DialogClose>
				<form onSubmit={(event) => void submit(event)} className="flex min-h-0 flex-col">
					<div className={settingsDialogHeaderClass}>
						<DialogTitle className="settings-dialog-title">{t("tickets.assignTitle", { plan: plan.title })}</DialogTitle>
						<DialogDescription className="text-control leading-4 text-settings-muted">
							{t("tickets.assignDescription")}
						</DialogDescription>
					</div>
					<div className={settingsDialogBodyClass}>
						<dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 rounded-md border border-border bg-surface px-3 py-2 text-2xs">
							{rows.map(([label, value]) => (
								<div key={label} className="contents">
									<dt className="settings-field-label">{label}</dt>
									<dd className="min-w-0 truncate font-mono text-foreground" title={value}>
										{value}
									</dd>
								</div>
							))}
						</dl>
						<p className="text-caption leading-4 text-settings-muted">{t("tickets.assignBranchHint")}</p>
						<TicketRoleFields projectId={ticket.projectId} value={values} onChange={setValues} disabled={busy} />
						<div className="flex flex-col gap-1.5" role="status">
							<span className="settings-field-label">{t("tickets.assignWarnings")}</span>
							{checking ? (
								<p className="text-caption leading-4 text-settings-muted">{t("tickets.assignChecking")}</p>
							) : warnings.length === 0 ? null : (
								<ul className="flex flex-col gap-1">
									{warnings.map((code) => (
										<li key={code} className="text-caption leading-4 text-warning" data-warning={code}>
											{assignWarningLabel(code, t)}
										</li>
									))}
								</ul>
							)}
						</div>
						{error ? (
							<p role="alert" className="text-caption leading-4 text-error">
								{error}
							</p>
						) : null}
					</div>
					<div className={settingsDialogFooterClass}>
						<DialogClose asChild>
							<Button type="button" variant="footer" disabled={busy}>
								{t("confirm.cancel")}
							</Button>
						</DialogClose>
						<Button type="submit" variant="footer-primary" disabled={busy || checking}>
							{busy ? t("tickets.starting") : terminating ? t("tickets.terminateAndStart") : t("tickets.start")}
						</Button>
					</div>
				</form>
			</DialogContent>
		</Dialog>
	);
}
