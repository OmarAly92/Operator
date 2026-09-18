import { useNavigate } from "@tanstack/react-router";
import { RotateCcw } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { ticketErrorMessage, useTicketMutations } from "../../hooks/useTicketMutations";
import { getTicketStatusView, type TicketWithProject } from "../../lib/ticket-presentation";
import { cn } from "../../lib/utils";
import { Tooltip, TooltipContent, TooltipTrigger } from "../ui/tooltip";

export function ArchiveTicketItem({ ticket }: { ticket: TicketWithProject }) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const { setArchived } = useTicketMutations();
	const [error, setError] = useState<string | null>(null);
	const status = getTicketStatusView(ticket, t);
	const reopen = async () => {
		setError(null);
		try {
			await setArchived.mutateAsync({ projectId: ticket.projectId, slug: ticket.slug, archived: false });
			void navigate({
				to: "/projects/$projectId/tickets/$slug",
				params: { projectId: ticket.projectId, slug: ticket.slug },
				search: {},
			});
		} catch (err) {
			setError(ticketErrorMessage(err, t, "tickets.reopenFailed"));
		}
	};
	return (
		<div
			className="group relative w-full rounded-xl border border-border bg-surface text-left"
			data-testid="archive-ticket-card"
			data-ticket-slug={ticket.slug}
			role="listitem"
		>
			<div className="absolute right-2 top-1.5 z-10">
				<Tooltip>
					<TooltipTrigger asChild>
						<button
							aria-label={t("tickets.reopenAria", { title: ticket.title })}
							className="grid size-control-board-sm shrink-0 place-items-center rounded-md text-passive transition-colors hover:bg-interactive-hover hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-accent/50 disabled:cursor-not-allowed disabled:opacity-35"
							disabled={setArchived.isPending}
							onClick={() => void reopen()}
							type="button"
						>
							<RotateCcw className={cn("size-icon-md", setArchived.isPending && "animate-spin")} aria-hidden="true" />
						</button>
					</TooltipTrigger>
					<TooltipContent side="top">{t("tickets.reopen")}</TooltipContent>
				</Tooltip>
			</div>
			<div className="flex flex-col gap-1.5 px-3.5 pb-2.5 pt-3 pr-8">
				<div className="line-clamp-2 text-base font-semibold leading-tight tracking-tight text-foreground" title={ticket.title}>
					{ticket.title}
				</div>
				<div className="flex min-w-0 items-center gap-2 font-mono text-micro text-passive">
					<span className="truncate rounded-sm border border-border bg-surface px-1 py-px">{ticket.projectName}</span>
					<span className={cn("font-sans text-2xs font-medium", status.className)}>{status.label}</span>
				</div>
			</div>
			{error ? (
				<div className="border-t border-border px-2 py-1.5 text-2xs text-destructive" role="alert">
					{error}
				</div>
			) : null}
		</div>
	);
}
