import type { TFunction } from "i18next";
import type { components } from "../../api/schema";
import { appI18n, type MessageKey } from "../i18n";

export type TicketView = components["schemas"]["TicketView"];
export type PlanView = components["schemas"]["PlanView"];
export type PlanStatus = PlanView["status"];
export type TicketStatus = TicketView["status"];
export type SessionTicketRef = components["schemas"]["SessionTicketRef"];
export type TicketWithProject = TicketView & { projectName: string };

export type PlanStatusView = {
	label: string;
	tone: string;
	className: string;
	dotClassName: string;
	breathe: boolean;
};

export type TicketStatusView = {
	label: string;
	tone: string;
	className: string;
	breathe: boolean;
};

type Tone = { tone: string; className: string; dotClassName: string };

const tones = {
	unknown: { tone: "var(--color-status-unknown)", className: "text-status-unknown", dotClassName: "bg-status-unknown" },
	idle: { tone: "var(--color-status-idle)", className: "text-status-idle", dotClassName: "bg-status-idle" },
	working: { tone: "var(--color-status-working)", className: "text-status-working", dotClassName: "bg-status-working" },
	needsYou: {
		tone: "var(--color-status-needs-you)",
		className: "text-status-needs-you",
		dotClassName: "bg-status-needs-you",
	},
	inReview: {
		tone: "var(--color-status-in-review)",
		className: "text-status-in-review",
		dotClassName: "bg-status-in-review",
	},
	ready: { tone: "var(--color-status-ready)", className: "text-status-ready", dotClassName: "bg-status-ready" },
	merged: { tone: "var(--color-status-merged)", className: "text-status-merged", dotClassName: "bg-status-merged" },
	terminated: {
		tone: "var(--color-status-terminated)",
		className: "text-status-terminated-foreground",
		dotClassName: "bg-status-terminated",
	},
} satisfies Record<string, Tone>;

export const PLAN_STATUS_MESSAGE_KEYS: Record<PlanStatus, MessageKey> = {
	todo: "tickets.plan.status.todo",
	idle: "tickets.plan.status.idle",
	working: "tickets.plan.status.working",
	needs_you: "tickets.plan.status.needs_you",
	in_review: "tickets.plan.status.in_review",
	reviewing: "tickets.plan.status.reviewing",
	awaiting_merge: "tickets.plan.status.awaiting_merge",
	merging: "tickets.plan.status.merging",
	merged: "tickets.plan.status.merged",
	done: "tickets.plan.status.done",
	terminated: "tickets.plan.status.terminated",
};

const planStatusBases: Record<PlanStatus, Tone & { breathe: boolean }> = {
	todo: { ...tones.unknown, breathe: false },
	idle: { ...tones.idle, breathe: false },
	working: { ...tones.working, breathe: true },
	needs_you: { ...tones.needsYou, breathe: false },
	in_review: { ...tones.inReview, breathe: false },
	reviewing: { ...tones.inReview, breathe: true },
	awaiting_merge: { ...tones.ready, breathe: false },
	merging: { ...tones.ready, breathe: true },
	merged: { ...tones.merged, breathe: false },
	done: { ...tones.merged, breathe: false },
	terminated: { ...tones.terminated, breathe: false },
};

export function getPlanStatusView(status: PlanStatus, t: TFunction = appI18n.t): PlanStatusView {
	const base = planStatusBases[status] ?? planStatusBases.todo;
	const key = PLAN_STATUS_MESSAGE_KEYS[status] ?? PLAN_STATUS_MESSAGE_KEYS.todo;
	return { ...base, label: t(key) };
}

export const TICKET_STATUS_MESSAGE_KEYS: Record<TicketStatus, MessageKey> = {
	draft: "tickets.status.draft",
	planning: "tickets.status.planning",
	ready: "tickets.status.ready",
	in_progress: "tickets.status.in_progress",
	awaiting_merge: "tickets.status.awaiting_merge",
	done: "tickets.status.done",
	archived: "tickets.status.archived",
};

const ticketStatusBases: Record<TicketStatus, Tone & { breathe: boolean }> = {
	draft: { ...tones.unknown, breathe: false },
	planning: { ...tones.working, breathe: true },
	ready: { ...tones.idle, breathe: false },
	in_progress: { ...tones.working, breathe: true },
	awaiting_merge: { ...tones.ready, breathe: false },
	done: { ...tones.merged, breathe: false },
	archived: { ...tones.terminated, breathe: false },
};

const mergedPlanStatuses = new Set<PlanStatus>(["merged", "done"]);

export function getTicketStatusView(ticket: TicketView, t: TFunction = appI18n.t): TicketStatusView {
	const base = ticketStatusBases[ticket.status] ?? ticketStatusBases.draft;
	const merged = ticket.plans.filter((plan) => mergedPlanStatuses.has(plan.status)).length;
	if (ticket.status === "in_progress" && merged > 0) {
		return { ...base, label: t("tickets.mergedCount", { merged, total: ticket.plans.length }) };
	}
	return { ...base, label: t(TICKET_STATUS_MESSAGE_KEYS[ticket.status] ?? TICKET_STATUS_MESSAGE_KEYS.draft) };
}

const archiveStatuses = new Set<TicketStatus>(["done", "archived"]);

export function isTicketInArchive(ticket: Pick<TicketView, "status">): boolean {
	return archiveStatuses.has(ticket.status);
}

export function openTicketCount(tickets: readonly Pick<TicketView, "status">[]): number {
	return tickets.filter((ticket) => !isTicketInArchive(ticket)).length;
}

export function planNumber(file: string): string {
	const match = /(?:^|\/)(\d+)-[^/]*$/.exec(file);
	return match?.[1] ?? "";
}

export function ticketBadgeLabel(ref: SessionTicketRef): string {
	if (ref.role === "planning" || !ref.planFile) return `${ref.slug} · plan`;
	const number = planNumber(ref.planFile);
	return `${ref.slug} · ${number || ref.planFile.split("/").pop() || ref.planFile}`;
}

export function splitFrontmatter(content: string): { fields: Array<[string, string]>; body: string } {
	if (!content.startsWith("---\n")) return { fields: [], body: content };
	const end = content.indexOf("\n---", 4);
	if (end === -1) return { fields: [], body: content };
	const header = content.slice(4, end);
	const rest = content.slice(end + 4);
	const fields: Array<[string, string]> = [];
	for (const line of header.split("\n")) {
		const colon = line.indexOf(":");
		if (colon === -1) continue;
		const key = line.slice(0, colon).trim();
		let value = line.slice(colon + 1).trim();
		if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
			try {
				value = JSON.parse(value) as string;
			} catch {
				value = value.slice(1, -1);
			}
		}
		if (key) fields.push([key, value]);
	}
	return { fields, body: rest.replace(/^\n+/, "") };
}

export function ticketFileGroups(ticket: TicketView): { docs: string[]; plans: Array<{ plan: PlanView; kickoff?: string }> } {
	const planFiles = new Set(ticket.plans.flatMap((plan) => [plan.file, plan.kickoffFile ?? ""]));
	const docs = ticket.files.filter((file) => !planFiles.has(file) && !file.startsWith("plans/"));
	const plans = [...ticket.plans]
		.sort((left, right) => left.order - right.order || left.file.localeCompare(right.file))
		.map((plan) => ({ plan, kickoff: plan.kickoffFile || undefined }));
	return { docs, plans };
}
