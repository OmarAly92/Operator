import type { TFunction } from "i18next";
import type { MessageKey } from "../i18n";
import { planNumber, type PlanView, type TicketWithProject } from "./ticket-presentation";

export type AssignWarning =
	| "plan_order"
	| "ticket_repo_dirty"
	| "ticket_not_on_default_branch"
	| "planning_active"
	| "plan_assigned";

export const ASSIGN_WARNINGS: readonly AssignWarning[] = [
	"plan_order",
	"ticket_repo_dirty",
	"ticket_not_on_default_branch",
	"planning_active",
	"plan_assigned",
];

const warningKeys: Record<AssignWarning, MessageKey> = {
	plan_order: "tickets.warning.plan_order",
	ticket_repo_dirty: "tickets.warning.ticket_repo_dirty",
	ticket_not_on_default_branch: "tickets.warning.ticket_not_on_default_branch",
	planning_active: "tickets.warning.planning_active",
	plan_assigned: "tickets.warning.plan_assigned",
};

function isAssignWarning(code: string): code is AssignWarning {
	return code in warningKeys;
}

export function assignWarningLabel(code: string, t: TFunction): string {
	return isAssignWarning(code) ? t(warningKeys[code]) : code;
}

export function needsForce(warnings: readonly string[]): boolean {
	return warnings.length > 0;
}

const assignableStatuses = new Set<PlanView["status"]>(["todo", "terminated"]);

export function canAssignPlan(plan: Pick<PlanView, "status">): boolean {
	return assignableStatuses.has(plan.status);
}

export function assignActionKey(plan: Pick<PlanView, "status">): "tickets.assign" | "tickets.reassign" {
	return plan.status === "terminated" ? "tickets.reassign" : "tickets.assign";
}

export function planBranchName(slug: string, file: string): string {
	const number = planNumber(file);
	const stem = file.split("/").pop()?.replace(/\.md$/, "") ?? file;
	return `opr/${slug}-${number || stem}`;
}

export type PlanDragData = { ticket: TicketWithProject; plan: PlanView };

export function planDragId(data: PlanDragData): string {
	return `plan:${data.ticket.projectId}:${data.ticket.slug}:${data.plan.file}`;
}

export const LANE_DROP_ID = "drop:lane:working";

const projectDropPrefix = "drop:project:";

export function projectDropId(projectId: string): string {
	return `${projectDropPrefix}${projectId}`;
}

export function dropAccepts(dropId: string, data: PlanDragData): boolean {
	if (dropId === LANE_DROP_ID) return true;
	if (dropId.startsWith(projectDropPrefix)) return dropId.slice(projectDropPrefix.length) === data.ticket.projectId;
	return false;
}
