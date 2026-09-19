import { useNavigate } from "@tanstack/react-router";
import { X } from "lucide-react";
import { RadioGroup } from "radix-ui";
import { useEffect, useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { ticketErrorMessage, useTicketMutations } from "../../hooks/useTicketMutations";
import type { PlanView, TicketView } from "../../lib/ticket-presentation";
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

type Reviewer = "planner" | "new";

export function ReviewPlanSheet({
	open,
	onOpenChange,
	ticket,
	plan,
}: {
	open: boolean;
	onOpenChange: (open: boolean) => void;
	ticket: Pick<TicketView, "projectId" | "slug" | "title">;
	plan: Pick<PlanView, "file" | "title">;
}) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const { reviewPlan } = useTicketMutations();
	const [reviewer, setReviewer] = useState<Reviewer>("planner");
	const [values, setValues] = useState<TicketRoleValues>(emptyTicketRoleValues);
	const [error, setError] = useState<string | null>(null);
	const busy = reviewPlan.isPending;

	useEffect(() => {
		if (!open) {
			setReviewer("planner");
			setValues(emptyTicketRoleValues);
			setError(null);
		}
	}, [open]);

	const submit = async (event: FormEvent<HTMLFormElement>) => {
		event.preventDefault();
		if (busy) return;
		setError(null);
		try {
			const result = await reviewPlan.mutateAsync({
				projectId: ticket.projectId,
				slug: ticket.slug,
				plan: plan.file,
				reviewer,
				...values,
			});
			onOpenChange(false);
			void navigate({
				to: "/projects/$projectId/sessions/$sessionId",
				params: { projectId: result.session.projectId || ticket.projectId, sessionId: result.session.id },
			});
		} catch (err) {
			setError(ticketErrorMessage(err, t, "tickets.reviewFailed"));
		}
	};

	const reviewers: Array<{ value: Reviewer; label: string }> = [
		{ value: "planner", label: t("tickets.reviewer.planner") },
		{ value: "new", label: t("tickets.reviewer.new") },
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
						<DialogTitle className="settings-dialog-title">{t("tickets.reviewTitle", { plan: plan.title })}</DialogTitle>
						<DialogDescription className="text-control leading-4 text-settings-muted">
							{t("tickets.reviewDescription")}
						</DialogDescription>
					</div>
					<div className={settingsDialogBodyClass}>
						<div className="flex flex-col gap-1.5">
							<span className="settings-field-label">{t("tickets.reviewer")}</span>
							<RadioGroup.Root
								aria-label={t("tickets.reviewer")}
								className="settings-segment self-start"
								value={reviewer}
								onValueChange={(next) => setReviewer(next as Reviewer)}
							>
								{reviewers.map((option) => (
									<RadioGroup.Item key={option.value} value={option.value} className="settings-segment-item">
										{option.label}
									</RadioGroup.Item>
								))}
							</RadioGroup.Root>
						</div>
						<TicketRoleFields projectId={ticket.projectId} value={values} onChange={setValues} disabled={busy} />
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
						<Button type="submit" variant="footer-primary" disabled={busy}>
							{busy ? t("tickets.starting") : t("tickets.review")}
						</Button>
					</div>
				</form>
			</DialogContent>
		</Dialog>
	);
}
