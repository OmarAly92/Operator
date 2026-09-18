import { AlertTriangle, GripVertical } from "lucide-react";
import type { KeyboardEvent, MouseEvent, PointerEvent } from "react";
import { useTranslation } from "react-i18next";
import { getAgentActivityView } from "../../lib/session-presentation";
import { assignActionKey, canAssignPlan } from "../../lib/ticket-assign";
import { getPlanStatusView, planNumber, type PlanView, type TicketWithProject } from "../../lib/ticket-presentation";
import { cn } from "../../lib/utils";
import type { WorkspaceSession } from "../../types/workspace";
import { usePlanDraggable } from "./TicketDndProvider";

export type PlanRowProps = {
	ticket: TicketWithProject;
	plan: PlanView;
	session?: WorkspaceSession;
	draggable?: boolean;
	onOpenSession: (sessionId: string) => void;
	onAssign?: (plan: PlanView) => void;
	onReview?: (plan: PlanView) => void;
	onMerge?: (plan: PlanView) => void;
	onMarkDone?: (plan: PlanView) => void;
	onOpenFile?: (file: string) => void;
	selectedFile?: string;
};

const reviewableStatuses = new Set<PlanView["status"]>(["idle", "working", "needs_you", "in_review", "terminated"]);
const closedStatuses = new Set<PlanView["status"]>(["merged", "done"]);

export function canReviewPlan(plan: PlanView): boolean {
	return Boolean(plan.sessionId) && reviewableStatuses.has(plan.status);
}

const rowActionClass =
	"inline-flex h-control-md shrink-0 items-center rounded-sm px-1.5 font-mono text-micro font-medium uppercase tracking-wide-sm transition-colors hover:bg-interactive-hover focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/60 disabled:opacity-50";

export function PlanRow({
	ticket,
	plan,
	session,
	draggable = false,
	onOpenSession,
	onAssign,
	onReview,
	onMerge,
	onMarkDone,
	onOpenFile,
	selectedFile,
}: PlanRowProps) {
	const { t } = useTranslation();
	const status = getPlanStatusView(plan.status, t);
	const activity = session ? getAgentActivityView(session.activity, t) : undefined;
	const number = planNumber(plan.file);
	const sessionId = plan.sessionId;
	const openSession = (event: MouseEvent | KeyboardEvent) => {
		event.stopPropagation();
		if (sessionId) onOpenSession(sessionId);
	};
	const stop = (event: MouseEvent<HTMLButtonElement>) => event.stopPropagation();
	const openFile = onOpenFile ? () => onOpenFile(plan.file) : undefined;
	const showMerge = plan.status === "awaiting_merge" && onMerge;
	const showReview = onReview && canReviewPlan(plan);
	const showDone = onMarkDone && !closedStatuses.has(plan.status);
	const selected = selectedFile === plan.file;
	const assignable = canAssignPlan(plan);
	const drag = usePlanDraggable({ ticket, plan }, draggable && assignable);
	const showAssign = onAssign && assignable;
	const showHandle = draggable && assignable;
	const dragListeners = drag.listeners ?? {};
	const handlePointerDown = (event: PointerEvent<HTMLButtonElement>) => {
		event.stopPropagation();
		dragListeners.onPointerDown?.(event);
	};
	const handleKeyDown = (event: KeyboardEvent<HTMLButtonElement>) => {
		event.stopPropagation();
		dragListeners.onKeyDown?.(event);
	};

	return (
		<div
			ref={drag.setNodeRef}
			className={cn(
				"flex flex-col gap-1 rounded-md px-1.5 py-1 text-2xs",
				selected && "bg-interactive-hover",
				drag.isDragging && "opacity-40",
			)}
			data-plan-file={plan.file}
			data-testid="ticket-plan-row"
		>
			<div className="flex min-w-0 items-center gap-2">
				{showHandle ? (
					<button
						ref={drag.setActivatorNodeRef}
						type="button"
						aria-label={t("tickets.dragHandleAria", { plan: plan.title })}
						className="inline-flex size-control-md shrink-0 cursor-grab items-center justify-center rounded-sm text-passive transition-colors hover:bg-interactive-hover hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/60 active:cursor-grabbing"
						{...drag.attributes}
						onClick={stop}
						onKeyDown={handleKeyDown}
						onPointerDown={handlePointerDown}
					>
						<GripVertical aria-hidden="true" className="size-icon-2xs" />
					</button>
				) : null}
				<span className="w-5 shrink-0 font-mono text-micro text-passive">{number || "·"}</span>
				{openFile ? (
					<button
						type="button"
						aria-current={selected ? "true" : undefined}
						className="min-w-0 flex-1 truncate text-left text-foreground hover:underline"
						onClick={openFile}
						title={plan.file}
					>
						{plan.title}
					</button>
				) : (
					<span className="min-w-0 flex-1 truncate text-foreground" title={plan.file}>
						{plan.title}
					</span>
				)}
				{plan.unordered ? (
					<AlertTriangle aria-label={t("tickets.unorderedPlan")} className="size-icon-2xs shrink-0 text-warning" />
				) : null}
				<span
					className={cn("inline-flex shrink-0 items-center gap-1.5 whitespace-nowrap font-medium", status.className)}
					style={activity && activity.state === "active" ? { color: activity.tone } : undefined}
				>
					<span
						aria-hidden="true"
						className={cn(
							"size-dot-sm shrink-0 rounded-full",
							activity && activity.state === "active" ? activity.indicatorClassName : status.dotClassName,
							!activity && status.breathe && "animate-status-pulse",
						)}
					/>
					{status.label}
				</span>
			</div>
			{sessionId || showAssign || showReview || showMerge || showDone ? (
				<div className="flex flex-wrap items-center gap-1 pl-7">
					{sessionId ? (
						<button
							type="button"
							aria-label={t("tickets.openSessionAria", { plan: plan.title })}
							className={cn(rowActionClass, "text-passive hover:text-foreground")}
							disabled={!session}
							onClick={openSession}
							title={session ? session.title : t("tickets.sessionMissing")}
						>
							{session ? session.title : t("tickets.sessionMissing")}
						</button>
					) : null}
					<span className="flex-1" />
					{showAssign ? (
						<button
							type="button"
							className={cn(rowActionClass, "text-foreground")}
							data-testid="plan-assign-button"
							onClick={(event) => {
								stop(event);
								onAssign(plan);
							}}
						>
							{t(assignActionKey(plan))}
						</button>
					) : null}
					{showReview ? (
						<button
							type="button"
							className={cn(rowActionClass, "text-status-in-review")}
							onClick={(event) => {
								stop(event);
								onReview(plan);
							}}
						>
							{t("tickets.review")}
						</button>
					) : null}
					{showMerge ? (
						<button
							type="button"
							className={cn(rowActionClass, "bg-status-ready/15 text-status-ready")}
							data-testid="plan-merge-button"
							onClick={(event) => {
								stop(event);
								onMerge(plan);
							}}
						>
							{t("tickets.merge")}
						</button>
					) : null}
					{showDone ? (
						<button
							type="button"
							className={cn(rowActionClass, "text-passive hover:text-foreground")}
							onClick={(event) => {
								stop(event);
								onMarkDone(plan);
							}}
						>
							{t("tickets.markDone")}
						</button>
					) : null}
				</div>
			) : null}
			{plan.warning ? (
				<p className="pl-7 text-micro text-warning" role="status">
					{plan.warning}
				</p>
			) : null}
		</div>
	);
}
