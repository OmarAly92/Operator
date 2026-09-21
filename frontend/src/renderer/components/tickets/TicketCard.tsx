import { useNavigate } from "@tanstack/react-router";
import { AlertTriangle } from "lucide-react";
import { useState, type KeyboardEvent, type MouseEvent } from "react";
import { useTranslation } from "react-i18next";
import { getAgentActivityView } from "../../lib/session-presentation";
import { getTicketStatusView, planNumber, type PlanView, type TicketWithProject } from "../../lib/ticket-presentation";
import { cn } from "../../lib/utils";
import type { WorkspaceSession } from "../../types/workspace";
import { MarkdownBody } from "../MarkdownBody";
import { MergeConfirmDialog } from "./MergeConfirmDialog";
import { PlanRow } from "./PlanRow";
import { PlanWithAgentSheet } from "./PlanWithAgentSheet";
import { ReviewPlanSheet } from "./ReviewPlanSheet";
import { useTicketDrag } from "./TicketDndProvider";

const liveSessionStatuses = new Set<WorkspaceSession["status"]>(["working", "idle", "needs_input", "no_signal"]);

const footerButtonClass =
	"inline-flex h-control-md items-center whitespace-nowrap rounded-sm px-2 text-2xs font-medium transition-colors hover:bg-interactive-hover focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/60";

export function TicketCard({
	ticket,
	sessionsById,
}: {
	ticket: TicketWithProject;
	sessionsById: ReadonlyMap<string, WorkspaceSession>;
}) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const { requestAssign } = useTicketDrag();
	const [planOpen, setPlanOpen] = useState(false);
	const [reviewPlan, setReviewPlan] = useState<PlanView | null>(null);
	const [mergePlan, setMergePlan] = useState<PlanView | null>(null);
	const status = getTicketStatusView(ticket, t);
	const planningSession = ticket.planningSessionId ? sessionsById.get(ticket.planningSessionId) : undefined;
	const planningLive = planningSession !== undefined && liveSessionStatuses.has(planningSession.status);
	const planningActivity = planningSession ? getAgentActivityView(planningSession.activity, t) : undefined;
	const showPlanningDot = ticket.status === "planning" && planningActivity !== undefined;
	const plans = [...ticket.plans].sort((left, right) => left.order - right.order || left.file.localeCompare(right.file));
	const awaiting = plans.filter((plan) => plan.status === "awaiting_merge");

	const openTicket = () =>
		void navigate({
			to: "/projects/$projectId/tickets/$slug",
			params: { projectId: ticket.projectId, slug: ticket.slug },
			search: {},
		});
	const openSession = (sessionId: string) =>
		void navigate({
			to: "/projects/$projectId/sessions/$sessionId",
			params: { projectId: ticket.projectId, sessionId },
		});
	const stop = (event: MouseEvent<HTMLButtonElement>) => event.stopPropagation();
	const handleKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
		if (event.currentTarget !== event.target) return;
		if (event.key !== "Enter" && event.key !== " ") return;
		event.preventDefault();
		openTicket();
	};

	return (
		<div
			className="group relative w-full cursor-pointer rounded-xl border border-border bg-surface text-left transition-[border-color,box-shadow] hover:border-border-strong hover:shadow-sm"
			data-testid="ticket-card"
			data-ticket-slug={ticket.slug}
			onClick={openTicket}
			onKeyDown={handleKeyDown}
			role="button"
			tabIndex={0}
		>
			<div className="flex flex-col gap-1 px-3 pb-2 pt-2.5">
				<div className="line-clamp-2 text-control font-semibold leading-tight tracking-tight text-foreground" title={ticket.title}>
					{ticket.title}
				</div>
				<div className="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1 font-mono text-micro text-passive">
					<span className="max-w-[45%] shrink-0 truncate rounded-sm border border-border bg-surface px-1 py-px">{ticket.projectName}</span>
					<span
						className={cn("inline-flex min-w-0 items-center gap-1.5 font-sans text-2xs font-medium", status.className)}
						style={showPlanningDot && planningActivity ? { color: planningActivity.tone } : undefined}
					>
						<span
							aria-hidden="true"
							className={cn(
								"size-dot-sm shrink-0 rounded-full",
								showPlanningDot && planningActivity ? planningActivity.indicatorClassName : "bg-current",
								!showPlanningDot && status.breathe && "animate-status-pulse",
							)}
						/>
						{status.label}
					</span>
				</div>
				{ticket.warning ? (
					<p className="flex items-start gap-1.5 text-micro text-warning" role="status">
						<AlertTriangle aria-hidden="true" className="mt-px size-icon-2xs shrink-0" />
						<span>{ticket.warning}</span>
					</p>
				) : null}
			</div>
			{plans.length > 0 ? (
				<>
					<div aria-hidden="true" className="mx-3 my-px h-px bg-border" />
					<div aria-label={t("tickets.plansAria", { title: ticket.title })} className="flex flex-col gap-0.5 px-2 py-1.5" role="list">
						{plans.map((plan) => (
							<div key={plan.file} role="listitem">
								<PlanRow
									ticket={ticket}
									plan={plan}
									draggable
									session={plan.sessionId ? sessionsById.get(plan.sessionId) : undefined}
									onOpenSession={openSession}
									onAssign={(target) => requestAssign(ticket, target)}
									onReview={(target) => setReviewPlan(target)}
								/>
							</div>
						))}
					</div>
				</>
			) : null}
			{awaiting.map((plan) => (
				<div
					key={plan.file}
					className="mx-3 mb-2 flex flex-col gap-1.5 rounded-md border border-status-ready/40 bg-status-ready/10 px-3 py-2"
					data-testid="ticket-awaiting-merge"
				>
					<span className="text-2xs font-medium text-status-ready">
						{planNumber(plan.file)} {plan.title} · {t("tickets.plan.status.awaiting_merge")}
					</span>
					{plan.mergeSummary ? <MarkdownBody body={plan.mergeSummary} clamped testId={`merge-summary-${plan.order}`} /> : null}
					<button
						type="button"
						className="inline-flex h-control-md items-center self-start rounded-sm bg-status-ready px-2.5 text-2xs font-semibold text-primary-foreground transition-opacity hover:opacity-90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/60"
						onClick={(event) => {
							stop(event);
							setMergePlan(plan);
						}}
					>
						{t("tickets.merge")}
					</button>
				</div>
			))}
			<div aria-hidden="true" className="mx-3 my-px h-px bg-border" />
			<div className="flex flex-wrap items-center gap-1 px-1.5 py-1">
				{planningLive && planningSession ? (
					<button
						type="button"
						className={cn(footerButtonClass, "text-foreground")}
						onClick={(event) => {
							stop(event);
							openSession(planningSession.id);
						}}
					>
						<span aria-hidden="true" className={cn("mr-1.5 size-dot-sm rounded-full", planningActivity?.indicatorClassName)} />
						{t("tickets.openPlanningSession")}
					</button>
				) : (
					<button
						type="button"
						className={cn(footerButtonClass, "text-foreground")}
						onClick={(event) => {
							stop(event);
							setPlanOpen(true);
						}}
					>
						{t("tickets.planWithAgent")}
					</button>
				)}
				<span className="flex-1" />
				<button
					type="button"
					className={cn(footerButtonClass, "text-passive hover:text-foreground")}
					onClick={(event) => {
						stop(event);
						openTicket();
					}}
				>
					{t("tickets.open")}
				</button>
			</div>
			<div onClick={(event) => event.stopPropagation()} onKeyDown={(event) => event.stopPropagation()}>
				<PlanWithAgentSheet open={planOpen} onOpenChange={setPlanOpen} ticket={ticket} />
				{reviewPlan ? (
					<ReviewPlanSheet open onOpenChange={(open) => !open && setReviewPlan(null)} ticket={ticket} plan={reviewPlan} />
				) : null}
				{mergePlan ? (
					<MergeConfirmDialog open onOpenChange={(open) => !open && setMergePlan(null)} ticket={ticket} plan={mergePlan} />
				) : null}
			</div>
		</div>
	);
}
