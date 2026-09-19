import { Plus } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import type { TicketProject } from "../../hooks/useTicketsQuery";
import { openTicketCount, type TicketWithProject } from "../../lib/ticket-presentation";
import { dotGlow } from "../../theme/effects";
import type { WorkspaceSession } from "../../types/workspace";
import { CreateTicketSheet } from "./CreateTicketSheet";
import { TicketCard } from "./TicketCard";

const columnTone = "var(--color-status-in-review)";

export function PlannedColumn({
	tickets,
	projects,
	sessionsById,
	isError,
	supportsTickets,
	defaultProjectId,
}: {
	tickets: TicketWithProject[];
	projects: readonly TicketProject[];
	sessionsById: ReadonlyMap<string, WorkspaceSession>;
	isError: boolean;
	supportsTickets: boolean;
	defaultProjectId?: string;
}) {
	const { t } = useTranslation();
	const [createOpen, setCreateOpen] = useState(false);
	const count = openTicketCount(tickets);

	return (
		<section
			aria-label={t("tickets.columnAria")}
			className="flex min-w-0 flex-col overflow-hidden"
			data-column="planned"
			data-testid="board-column"
		>
			<div className="flex h-12 shrink-0 items-center gap-2 px-3">
				<span className="size-dot-sm rounded-full" style={{ background: columnTone, boxShadow: dotGlow(columnTone) }} />
				<span className="font-mono text-2xs font-medium uppercase tracking-wide-sm text-status-in-review">
					{t("tickets.column")}
				</span>
				<span aria-label={t("tickets.columnCountAria", { count })} className="ml-auto font-mono text-2xs leading-none text-passive">
					{count}
				</span>
				<button
					type="button"
					aria-label={t("tickets.create")}
					className="inline-flex size-control-md items-center justify-center rounded-sm text-passive transition-colors hover:bg-interactive-hover hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/60 disabled:opacity-40"
					disabled={!supportsTickets}
					onClick={() => setCreateOpen(true)}
					title={t("tickets.create")}
				>
					<Plus aria-hidden="true" className="size-icon-sm" />
				</button>
			</div>
			<div className="board-scrollbar min-h-0 flex-1 overflow-y-auto px-3 pb-3 pt-3">
				<div className="flex min-h-full flex-col gap-2.5">
					{!supportsTickets ? (
						<p className="px-1 text-2xs leading-relaxed text-passive">{t("tickets.needsRepo")}</p>
					) : isError && tickets.length === 0 ? (
						<p className="px-1 text-2xs leading-relaxed text-error" role="alert">
							{t("tickets.loadFailed")}
						</p>
					) : tickets.length === 0 ? (
						<div className="px-1 text-2xs leading-relaxed text-passive">
							<p className="font-medium text-muted-foreground">{t("tickets.empty")}</p>
							<p>{t("tickets.emptyHint")}</p>
						</div>
					) : (
						tickets.map((ticket) => (
							<TicketCard key={`${ticket.projectId}:${ticket.slug}`} ticket={ticket} sessionsById={sessionsById} />
						))
					)}
				</div>
			</div>
			<CreateTicketSheet open={createOpen} onOpenChange={setCreateOpen} projects={projects} defaultProjectId={defaultProjectId} />
		</section>
	);
}
