import { describe, expect, it } from "vitest";
import { appI18n } from "../i18n";
import type { PlanView, TicketWithProject } from "./ticket-presentation";
import {
	ASSIGN_WARNINGS,
	assignActionKey,
	assignWarningLabel,
	canAssignPlan,
	dropAccepts,
	LANE_DROP_ID,
	needsForce,
	planBranchName,
	planDragId,
	projectDropId,
} from "./ticket-assign";

const ticket: TicketWithProject = {
	projectId: "p1",
	projectName: "app",
	slug: "search-page",
	title: "Search page",
	status: "ready",
	plans: [],
	files: [],
};

function plan(status: PlanView["status"], file = "plans/01-index.md"): PlanView {
	return { file, order: 1, title: "Index", status };
}

describe("assign warnings", () => {
	it("lists the five daemon warnings in daemon order", () => {
		expect(ASSIGN_WARNINGS).toEqual([
			"plan_order",
			"ticket_repo_dirty",
			"ticket_not_on_default_branch",
			"planning_active",
			"plan_assigned",
		]);
	});

	it("maps every known warning to copy and echoes unknown codes", () => {
		for (const code of ASSIGN_WARNINGS) {
			expect(assignWarningLabel(code, appI18n.t)).not.toBe(code);
		}
		expect(assignWarningLabel("plan_assigned", appI18n.t)).toBe(
			"This plan already has a live session. Starting again terminates it first.",
		);
		expect(assignWarningLabel("something_new", appI18n.t)).toBe("something_new");
	});

	it("needs force whenever the dry run returned anything", () => {
		expect(needsForce([])).toBe(false);
		expect(needsForce(["ticket_repo_dirty"])).toBe(true);
	});
});

describe("assignable plans", () => {
	it("allows todo and terminated plans only", () => {
		expect(canAssignPlan(plan("todo"))).toBe(true);
		expect(canAssignPlan(plan("terminated"))).toBe(true);
		for (const status of ["idle", "working", "needs_you", "in_review", "reviewing", "awaiting_merge", "merging", "merged", "done"] as const) {
			expect(canAssignPlan(plan(status))).toBe(false);
		}
	});

	it("labels the action Assign for todo and Reassign for terminated", () => {
		expect(assignActionKey(plan("todo"))).toBe("tickets.assign");
		expect(assignActionKey(plan("terminated"))).toBe("tickets.reassign");
	});
});

describe("planBranchName", () => {
	it("uses the NN prefix like the daemon", () => {
		expect(planBranchName("search-page", "plans/01-index.md")).toBe("opr/search-page-01");
		expect(planBranchName("search-page", "plans/12-ui.md")).toBe("opr/search-page-12");
	});

	it("falls back to the file stem for unnumbered plans", () => {
		expect(planBranchName("search-page", "plans/cleanup.md")).toBe("opr/search-page-cleanup");
	});
});

describe("drag and drop ids", () => {
	const data = { ticket, plan: plan("todo") };

	it("builds a stable draggable id from project, slug and file", () => {
		expect(planDragId(data)).toBe("plan:p1:search-page:plans/01-index.md");
	});

	it("lets the lane accept any plan and a project header only its own", () => {
		expect(dropAccepts(LANE_DROP_ID, data)).toBe(true);
		expect(dropAccepts(projectDropId("p1"), data)).toBe(true);
		expect(dropAccepts(projectDropId("p2"), data)).toBe(false);
		expect(dropAccepts("something-else", data)).toBe(false);
	});
});
