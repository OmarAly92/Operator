import { useNavigate } from "@tanstack/react-router";
import { X } from "lucide-react";
import { useEffect, useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { ticketErrorMessage, useTicketMutations } from "../../hooks/useTicketMutations";
import type { TicketView } from "../../lib/ticket-presentation";
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

export function PlanWithAgentSheet({
	open,
	onOpenChange,
	ticket,
}: {
	open: boolean;
	onOpenChange: (open: boolean) => void;
	ticket: Pick<TicketView, "projectId" | "slug" | "title">;
}) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const { planTicket } = useTicketMutations();
	const [values, setValues] = useState<TicketRoleValues>(emptyTicketRoleValues);
	const [error, setError] = useState<string | null>(null);
	const busy = planTicket.isPending;

	useEffect(() => {
		if (!open) {
			setValues(emptyTicketRoleValues);
			setError(null);
		}
	}, [open]);

	const submit = async (event: FormEvent<HTMLFormElement>) => {
		event.preventDefault();
		if (busy) return;
		setError(null);
		try {
			const session = await planTicket.mutateAsync({ projectId: ticket.projectId, slug: ticket.slug, ...values });
			onOpenChange(false);
			void navigate({
				to: "/projects/$projectId/sessions/$sessionId",
				params: { projectId: session.projectId || ticket.projectId, sessionId: session.id },
			});
		} catch (err) {
			setError(ticketErrorMessage(err, t, "tickets.planFailed"));
		}
	};

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
						<DialogTitle className="settings-dialog-title">{t("tickets.planWithAgent")}</DialogTitle>
						<DialogDescription className="text-control leading-4 text-settings-muted">
							{ticket.title} · {t("tickets.planDescription")}
						</DialogDescription>
					</div>
					<div className={settingsDialogBodyClass}>
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
							{busy ? t("tickets.starting") : t("tickets.start")}
						</Button>
					</div>
				</form>
			</DialogContent>
		</Dialog>
	);
}
