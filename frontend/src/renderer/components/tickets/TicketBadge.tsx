import { useNavigate } from "@tanstack/react-router";
import { Ticket } from "lucide-react";
import type { MouseEvent } from "react";
import { useTranslation } from "react-i18next";
import { ticketBadgeLabel, type SessionTicketRef } from "../../lib/ticket-presentation";
import { cn } from "../../lib/utils";

export function TicketBadge({
	projectId,
	ticket,
	className,
}: {
	projectId: string;
	ticket: SessionTicketRef;
	className?: string;
}) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const label = ticketBadgeLabel(ticket);
	const open = (event: MouseEvent<HTMLButtonElement>) => {
		event.stopPropagation();
		void navigate({
			to: "/projects/$projectId/tickets/$slug",
			params: { projectId, slug: ticket.slug },
			search: { file: ticket.planFile },
		});
	};
	return (
		<button
			type="button"
			aria-label={t("tickets.badgeAria", { label })}
			className={cn(
				"inline-flex max-w-branch-chip shrink-0 items-center gap-1 truncate rounded-sm bg-accent/12 px-1.5 py-0.5 font-mono text-micro text-accent transition-colors hover:bg-accent/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/60",
				className,
			)}
			data-testid="session-ticket-badge"
			onClick={open}
			title={label}
		>
			<Ticket aria-hidden="true" className="size-icon-2xs shrink-0" />
			<span className="truncate">{label}</span>
		</button>
	);
}
