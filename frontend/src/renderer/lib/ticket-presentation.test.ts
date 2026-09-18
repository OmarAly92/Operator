import { describe, expect, it } from "vitest";
import {
	getPlanStatusView,
	getTicketStatusView,
	isTicketInArchive,
	openTicketCount,
	planNumber,
	splitFrontmatter,
	ticketBadgeLabel,
	ticketFileGroups,
	type PlanStatus,
	type PlanView,
	type TicketView,
} from "./ticket-presentation";

function plan(overrides: Partial<PlanView>): PlanView {
	return { file: "plans/01-daemon.md", order: 1, title: "Daemon", status: "todo", ...overrides };
}

function ticket(overrides: Partial<TicketView>): TicketView {
	return {
		projectId: "p1",
		slug: "planning-tickets",
		title: "Planning tickets",
		status: "draft",
		plans: [],
		files: ["ticket.md", "spec.md"],
		...overrides,
	};
}

const everyPlanStatus: PlanStatus[] = [
	"todo",
	"idle",
	"working",
	"needs_you",
	"in_review",
	"reviewing",
	"awaiting_merge",
	"merging",
	"merged",
	"done",
	"terminated",
];

describe("getPlanStatusView", () => {
	it("gives every daemon plan status a label and a colour token", () => {
		for (const status of everyPlanStatus) {
			const view = getPlanStatusView(status);
			expect(view.label, status).not.toBe("");
			expect(view.tone, status).toMatch(/^var\(--color-status-/);
			expect(view.className, status).toMatch(/^text-status-/);
		}
	});

	it("breathes only while an agent is actively doing something", () => {
		expect(getPlanStatusView("working").breathe).toBe(true);
		expect(getPlanStatusView("merging").breathe).toBe(true);
		expect(getPlanStatusView("reviewing").breathe).toBe(true);
		expect(getPlanStatusView("awaiting_merge").breathe).toBe(false);
		expect(getPlanStatusView("todo").breathe).toBe(false);
	});

	it("reads the awaiting merge status as the user's confirmation", () => {
		expect(getPlanStatusView("awaiting_merge").label).toBe("Awaiting your merge");
		expect(getPlanStatusView("awaiting_merge").tone).toBe("var(--color-status-ready)");
	});
});

describe("getTicketStatusView", () => {
	it("labels plain statuses", () => {
		expect(getTicketStatusView(ticket({ status: "draft" })).label).toBe("Draft");
		expect(getTicketStatusView(ticket({ status: "planning" })).label).toBe("Planning");
		expect(getTicketStatusView(ticket({ status: "ready" })).label).toBe("Ready");
		expect(getTicketStatusView(ticket({ status: "done" })).label).toBe("Done");
		expect(getTicketStatusView(ticket({ status: "archived" })).label).toBe("Archived");
	});

	it("counts merged plans while work is in progress", () => {
		const view = getTicketStatusView(
			ticket({
				status: "in_progress",
				plans: [
					plan({ status: "merged" }),
					plan({ file: "plans/02-board.md", order: 2, status: "done" }),
					plan({ file: "plans/03-assign.md", order: 3, status: "working" }),
					plan({ file: "plans/04-mobile.md", order: 4, status: "todo" }),
				],
			}),
		);
		expect(view.label).toBe("2/4 merged");
	});

	it("says in progress when nothing has merged yet", () => {
		const view = getTicketStatusView(ticket({ status: "in_progress", plans: [plan({ status: "working" })] }));
		expect(view.label).toBe("In progress");
		expect(view.breathe).toBe(true);
	});

	it("asks for confirmation when a plan awaits merge", () => {
		const view = getTicketStatusView(ticket({ status: "awaiting_merge", plans: [plan({ status: "awaiting_merge" })] }));
		expect(view.label).toBe("Waiting for your confirmation");
		expect(view.tone).toBe("var(--color-status-ready)");
	});
});

describe("helpers", () => {
	it("puts done and archived tickets in the archive", () => {
		expect(isTicketInArchive({ status: "done" })).toBe(true);
		expect(isTicketInArchive({ status: "archived" })).toBe(true);
		expect(isTicketInArchive({ status: "in_progress" })).toBe(false);
		expect(openTicketCount([{ status: "draft" }, { status: "done" }, { status: "archived" }, { status: "ready" }])).toBe(2);
	});

	it("extracts the plan number from the file name", () => {
		expect(planNumber("plans/01-daemon.md")).toBe("01");
		expect(planNumber("plans/12-mobile.kickoff.md")).toBe("12");
		expect(planNumber("plans/notes.md")).toBe("");
	});

	it("builds the session badge label", () => {
		expect(ticketBadgeLabel({ slug: "tickets", role: "planning" })).toBe("tickets · plan");
		expect(ticketBadgeLabel({ slug: "tickets", role: "implementing", planFile: "plans/02-board.md" })).toBe("tickets · 02");
		expect(ticketBadgeLabel({ slug: "tickets", role: "reviewing", planFile: "plans/02-board.md" })).toBe("tickets · 02");
		expect(ticketBadgeLabel({ slug: "tickets", role: "implementing", planFile: "plans/odd.md" })).toBe("tickets · odd.md");
	});

	it("splits YAML frontmatter from the body", () => {
		const parsed = splitFrontmatter('---\ntitle: "Daemon"\nstatus: ready\n---\n\n# Plan\n\nBody');
		expect(parsed.fields).toEqual([
			["title", "Daemon"],
			["status", "ready"],
		]);
		expect(parsed.body).toBe("# Plan\n\nBody");
	});

	it("leaves content without frontmatter alone", () => {
		expect(splitFrontmatter("# Just markdown\n")).toEqual({ fields: [], body: "# Just markdown\n" });
		expect(splitFrontmatter("---\nnot closed")).toEqual({ fields: [], body: "---\nnot closed" });
	});

	it("groups docs and plans with their kickoff files", () => {
		const groups = ticketFileGroups(
			ticket({
				files: ["ticket.md", "spec.md", "plans/01-daemon.md", "plans/01-daemon.kickoff.md", "plans/02-board.md"],
				plans: [plan({ kickoffFile: "plans/01-daemon.kickoff.md" }), plan({ file: "plans/02-board.md", order: 2, title: "Board" })],
			}),
		);
		expect(groups.docs).toEqual(["ticket.md", "spec.md"]);
		expect(groups.plans.map((entry) => [entry.plan.file, entry.kickoff])).toEqual([
			["plans/01-daemon.md", "plans/01-daemon.kickoff.md"],
			["plans/02-board.md", undefined],
		]);
	});
});
