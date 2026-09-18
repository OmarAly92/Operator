import { useNavigate } from "@tanstack/react-router";
import { X } from "lucide-react";
import { useEffect, useId, useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { ticketErrorMessage, useTicketMutations } from "../../hooks/useTicketMutations";
import type { TicketProject } from "../../hooks/useTicketsQuery";
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
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../ui/select";

export function CreateTicketSheet({
	open,
	onOpenChange,
	projects,
	defaultProjectId,
}: {
	open: boolean;
	onOpenChange: (open: boolean) => void;
	projects: readonly TicketProject[];
	defaultProjectId?: string;
}) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const { createTicket } = useTicketMutations();
	const projectSelectId = useId();
	const titleId = useId();
	const briefId = useId();
	const firstProjectId = projects[0]?.id ?? "";
	const [projectId, setProjectId] = useState(defaultProjectId ?? firstProjectId);
	const [title, setTitle] = useState("");
	const [brief, setBrief] = useState("");
	const [error, setError] = useState<string | null>(null);
	const busy = createTicket.isPending;
	const selectedProject = projects.find((project) => project.id === projectId) ?? projects[0];
	const canSubmit = !busy && title.trim() !== "" && selectedProject !== undefined;

	useEffect(() => {
		if (!open) {
			setTitle("");
			setBrief("");
			setError(null);
			return;
		}
		setProjectId(defaultProjectId ?? firstProjectId);
	}, [defaultProjectId, firstProjectId, open]);

	const submit = async (event: FormEvent<HTMLFormElement>) => {
		event.preventDefault();
		if (!canSubmit || !selectedProject) return;
		setError(null);
		try {
			const result = await createTicket.mutateAsync({
				projectId: selectedProject.id,
				title: title.trim(),
				brief: brief.trim(),
			});
			onOpenChange(false);
			void navigate({
				to: "/projects/$projectId/tickets/$slug",
				params: { projectId: result.ticket.projectId, slug: result.ticket.slug },
				search: {},
			});
		} catch (err) {
			setError(ticketErrorMessage(err, t, "tickets.createFailed"));
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
						<DialogTitle className="settings-dialog-title">{t("tickets.create")}</DialogTitle>
						<DialogDescription className="text-control leading-4 text-settings-muted">
							{t("tickets.createDescription")}
						</DialogDescription>
					</div>
					<div className={settingsDialogBodyClass}>
						{projects.length > 1 ? (
							<div className="flex flex-col gap-1.5">
								<label className="settings-field-label" htmlFor={projectSelectId}>
									{t("tickets.project")}
								</label>
								<Select value={selectedProject?.id ?? ""} onValueChange={setProjectId}>
									<SelectTrigger id={projectSelectId}>
										<SelectValue>{selectedProject?.name}</SelectValue>
									</SelectTrigger>
									<SelectContent align="start" position="popper">
										{projects.map((project) => (
											<SelectItem key={project.id} value={project.id}>
												{project.name}
											</SelectItem>
										))}
									</SelectContent>
								</Select>
							</div>
						) : null}
						<div className="flex flex-col gap-1.5">
							<label className="settings-field-label" htmlFor={titleId}>
								{t("tickets.title")}
							</label>
							<input
								id={titleId}
								autoFocus
								className="settings-field-control h-(--size-settings-action-height)"
								disabled={busy}
								maxLength={200}
								value={title}
								onChange={(event) => setTitle(event.target.value)}
								placeholder={t("tickets.titlePlaceholder")}
							/>
						</div>
						<div className="flex flex-col gap-1.5">
							<label className="settings-field-label" htmlFor={briefId}>
								{t("tickets.brief")}
							</label>
							<textarea
								id={briefId}
								className="settings-field-control min-h-(--size-textarea-min) resize-y py-2.5"
								disabled={busy}
								maxLength={4000}
								value={brief}
								onChange={(event) => setBrief(event.target.value)}
								placeholder={t("tickets.briefPlaceholder")}
							/>
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
						<Button type="submit" variant="footer-primary" disabled={!canSubmit}>
							{busy ? t("tickets.creating") : t("tickets.create")}
						</Button>
					</div>
				</form>
			</DialogContent>
		</Dialog>
	);
}
