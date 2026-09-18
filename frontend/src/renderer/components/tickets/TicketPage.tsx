import { useNavigate } from "@tanstack/react-router";
import { AlertTriangle, Archive, ArchiveRestore, FileText } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { ticketErrorMessage, useTicketMutations } from "../../hooks/useTicketMutations";
import { useTicketFileQuery, useTicketQuery } from "../../hooks/useTicketsQuery";
import { useWorkspaceQuery } from "../../hooks/useWorkspaceQuery";
import { formatTimeCompact } from "../../lib/format-time";
import { getAgentActivityView } from "../../lib/session-presentation";
import {
	getTicketStatusView,
	isTicketInArchive,
	splitFrontmatter,
	ticketFileGroups,
	type PlanView,
	type TicketView,
} from "../../lib/ticket-presentation";
import { cn } from "../../lib/utils";
import type { WorkspaceSession } from "../../types/workspace";
import { MarkdownBody } from "../MarkdownBody";
import { StatusPill } from "../StatusPill";
import { TopbarButton } from "../TopbarButton";
import { MergeConfirmDialog } from "./MergeConfirmDialog";
import { PlanRow } from "./PlanRow";
import { PlanWithAgentSheet } from "./PlanWithAgentSheet";
import { ReviewPlanSheet } from "./ReviewPlanSheet";

const liveSessionStatuses = new Set<WorkspaceSession["status"]>(["working", "idle", "needs_input", "no_signal"]);

function defaultFile(ticket: TicketView): string | undefined {
	if (ticket.files.includes("spec.md")) return "spec.md";
	return ticket.files[0];
}

export function TicketPage({ projectId, slug, file }: { projectId: string; slug: string; file?: string }) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const ticketQuery = useTicketQuery(projectId, slug);
	const ticket = ticketQuery.data;
	const selectedFile = file ?? (ticket ? defaultFile(ticket) : undefined);
	const fileQuery = useTicketFileQuery(projectId, slug, selectedFile);
	const workspaces = useWorkspaceQuery().data ?? [];
	const sessionsById = new Map<string, WorkspaceSession>();
	for (const workspace of workspaces) {
		if (workspace.id !== projectId) continue;
		for (const session of workspace.sessions) sessionsById.set(session.id, session);
	}
	const { markPlanDone, setArchived } = useTicketMutations();
	const [planOpen, setPlanOpen] = useState(false);
	const [reviewPlan, setReviewPlan] = useState<PlanView | null>(null);
	const [mergePlan, setMergePlan] = useState<PlanView | null>(null);
	const [actionError, setActionError] = useState<string | null>(null);

	const openFile = (next: string) =>
		void navigate({
			to: "/projects/$projectId/tickets/$slug",
			params: { projectId, slug },
			search: { file: next },
			replace: true,
		});
	const openSession = (sessionId: string) =>
		void navigate({ to: "/projects/$projectId/sessions/$sessionId", params: { projectId, sessionId } });

	if (ticketQuery.isError) {
		return (
			<p className="py-10 text-center text-xs text-passive" role="alert">
				{ticketErrorMessage(ticketQuery.error, t, "tickets.notFound")}
			</p>
		);
	}
	if (!ticket) return null;

	const status = getTicketStatusView(ticket, t);
	const groups = ticketFileGroups(ticket);
	const planningSession = ticket.planningSessionId ? sessionsById.get(ticket.planningSessionId) : undefined;
	const planningLive = planningSession !== undefined && liveSessionStatuses.has(planningSession.status);
	const planningActivity = planningSession ? getAgentActivityView(planningSession.activity, t) : undefined;
	const inArchive = isTicketInArchive(ticket);
	const runAction = async (
		action: () => Promise<unknown>,
		fallbackKey: "tickets.markDoneFailed" | "tickets.archiveFailed" | "tickets.reopenFailed",
	) => {
		setActionError(null);
		try {
			await action();
		} catch (err) {
			setActionError(ticketErrorMessage(err, t, fallbackKey));
		}
	};
	const fileButtonClass = (active: boolean) =>
		cn(
			"flex w-full min-w-0 items-center gap-2 rounded-md px-2 py-1 text-left text-2xs text-foreground transition-colors hover:bg-interactive-hover",
			active && "bg-interactive-hover font-medium",
		);
	const fileContent = fileQuery.data;
	const parsed = fileContent ? splitFrontmatter(fileContent.content) : undefined;
	const selectedPlan = ticket.plans.find((plan) => plan.file === selectedFile);
	const fileWarning = selectedFile === "ticket.md" ? ticket.warning : selectedPlan?.warning;

	return (
		<div className="flex h-full min-h-0 bg-background text-foreground" data-testid="ticket-page">
			<aside className="flex w-72 shrink-0 flex-col border-r border-border-strong">
				<div className="flex flex-col gap-2 border-b border-border-strong px-4 py-3">
					<div className="flex items-start justify-between gap-2">
						<h1 className="min-w-0 text-base font-semibold leading-tight tracking-tight" title={ticket.title}>
							{ticket.title}
						</h1>
						<StatusPill label={status.label} tone={status.tone} breathe={status.breathe} leading="none" />
					</div>
					{ticket.brief ? <p className="text-2xs leading-relaxed text-muted-foreground">{ticket.brief}</p> : null}
					{ticket.warning ? (
						<p className="flex items-start gap-1.5 text-micro text-warning" role="status">
							<AlertTriangle aria-hidden="true" className="mt-px size-icon-2xs shrink-0" />
							<span>{ticket.warning}</span>
						</p>
					) : null}
				</div>
				<nav aria-label={t("tickets.filesAria")} className="board-scrollbar min-h-0 flex-1 overflow-y-auto px-2 py-2">
					<p className="px-2 pb-1 font-mono text-micro uppercase tracking-wide-sm text-passive">{t("tickets.files")}</p>
					{groups.docs.map((doc) => (
						<button
							key={doc}
							type="button"
							aria-current={selectedFile === doc ? "true" : undefined}
							className={fileButtonClass(selectedFile === doc)}
							onClick={() => openFile(doc)}
						>
							<FileText aria-hidden="true" className="size-icon-2xs shrink-0 text-passive" />
							<span className="truncate">{doc}</span>
						</button>
					))}
					<p className="px-2 pb-1 pt-3 font-mono text-micro uppercase tracking-wide-sm text-passive">{t("tickets.plans")}</p>
					<div aria-label={t("tickets.plansAria", { title: ticket.title })} className="flex flex-col gap-0.5" role="list">
						{groups.plans.map(({ plan, kickoff }) => (
							<div key={plan.file} role="listitem">
								<PlanRow
									plan={plan}
									session={plan.sessionId ? sessionsById.get(plan.sessionId) : undefined}
									selectedFile={selectedFile}
									onOpenFile={openFile}
									onOpenSession={openSession}
									onReview={(target) => setReviewPlan(target)}
									onMerge={(target) => setMergePlan(target)}
									onMarkDone={(target) =>
										void runAction(
											() => markPlanDone.mutateAsync({ projectId, slug, plan: target.file }),
											"tickets.markDoneFailed",
										)
									}
								/>
								{kickoff ? (
									<button
										type="button"
										aria-current={selectedFile === kickoff ? "true" : undefined}
										className={cn(fileButtonClass(selectedFile === kickoff), "pl-9")}
										onClick={() => openFile(kickoff)}
										title={kickoff}
									>
										<FileText aria-hidden="true" className="size-icon-2xs shrink-0 text-passive" />
										<span className="truncate">{t("tickets.kickoff")}</span>
									</button>
								) : null}
							</div>
						))}
					</div>
					{planningSession ? (
						<button
							type="button"
							className={cn(fileButtonClass(false), "mt-3")}
							onClick={() => openSession(planningSession.id)}
						>
							<span
								aria-hidden="true"
								className={cn("size-dot-sm shrink-0 rounded-full", planningActivity?.indicatorClassName)}
							/>
							<span className="truncate">{t("tickets.planningSession")}</span>
							<span className="ml-auto truncate font-mono text-micro text-passive">{planningSession.title}</span>
						</button>
					) : null}
				</nav>
				<div className="flex flex-col gap-2 border-t border-border-strong px-3 py-3">
					{actionError ? (
						<p role="alert" className="text-micro text-error">
							{actionError}
						</p>
					) : null}
					<div className="flex flex-wrap items-center gap-2">
						{planningLive && planningSession ? (
							<TopbarButton className="whitespace-nowrap" variant="primary" onClick={() => openSession(planningSession.id)}>
								{t("tickets.openPlanningSession")}
							</TopbarButton>
						) : (
							<TopbarButton variant="primary" onClick={() => setPlanOpen(true)}>
								{t("tickets.planWithAgent")}
							</TopbarButton>
						)}
						<TopbarButton
							aria-label={inArchive ? t("tickets.reopenAria", { title: ticket.title }) : t("tickets.archiveAria", { title: ticket.title })}
							disabled={setArchived.isPending}
							onClick={() =>
								void runAction(
									() => setArchived.mutateAsync({ projectId, slug, archived: !inArchive }),
									inArchive ? "tickets.reopenFailed" : "tickets.archiveFailed",
								)
							}
						>
							{inArchive ? (
								<ArchiveRestore aria-hidden="true" className="size-icon-md" />
							) : (
								<Archive aria-hidden="true" className="size-icon-md" />
							)}
							{inArchive ? t("tickets.reopen") : t("tickets.archive")}
						</TopbarButton>
					</div>
				</div>
			</aside>
			<section className="flex min-w-0 flex-1 flex-col">
				<div className="flex h-toolbar shrink-0 items-center gap-2 border-b border-border-strong px-4">
					<span className="min-w-0 truncate font-mono text-2xs text-foreground">{selectedFile ?? ""}</span>
					<span className="min-w-0 flex-1" />
					{fileContent ? (
						<span className="font-mono text-micro text-passive">
							{t("tickets.fileModified", { time: formatTimeCompact(fileContent.modifiedAt) })}
						</span>
					) : null}
				</div>
				<div className="board-scrollbar min-h-0 flex-1 overflow-y-auto px-6 py-5">
					{fileWarning ? (
						<p className="mb-4 flex items-start gap-1.5 rounded-md border border-warning/40 bg-warning/10 px-3 py-2 text-2xs text-warning" role="status">
							<AlertTriangle aria-hidden="true" className="mt-px size-icon-2xs shrink-0" />
							<span>{fileWarning}</span>
						</p>
					) : null}
					{fileQuery.isError ? (
						<p className="text-2xs text-error" role="alert">
							{ticketErrorMessage(fileQuery.error, t, "tickets.fileLoadFailed")}
						</p>
					) : null}
					{parsed && parsed.fields.length > 0 ? (
						<dl
							aria-label={t("tickets.frontmatter")}
							className="mb-4 grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 rounded-md border border-border bg-surface px-3 py-2 font-mono text-micro"
						>
							{parsed.fields.map(([key, value]) => (
								<div key={key} className="contents">
									<dt className="text-passive">{key}</dt>
									<dd className="min-w-0 truncate text-foreground">{value}</dd>
								</div>
							))}
						</dl>
					) : null}
					{parsed ? <MarkdownBody body={parsed.body} className="max-w-3xl text-sm text-foreground" testId="ticket-file-preview" /> : null}
				</div>
			</section>
			<PlanWithAgentSheet open={planOpen} onOpenChange={setPlanOpen} ticket={ticket} />
			{reviewPlan ? (
				<ReviewPlanSheet open onOpenChange={(open) => !open && setReviewPlan(null)} ticket={ticket} plan={reviewPlan} />
			) : null}
			{mergePlan ? (
				<MergeConfirmDialog open onOpenChange={(open) => !open && setMergePlan(null)} ticket={ticket} plan={mergePlan} />
			) : null}
		</div>
	);
}
