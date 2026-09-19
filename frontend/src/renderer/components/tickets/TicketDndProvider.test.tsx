import { act, fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { LANE_DROP_ID, projectDropId } from "../../lib/ticket-assign";
import type { PlanView, TicketWithProject } from "../../lib/ticket-presentation";

vi.mock("./AssignPlanSheet", () => ({
	AssignPlanSheet: ({ plan, ticket }: { plan: { file: string }; ticket: { slug: string } }) => (
		<div data-testid="assign-sheet">
			{ticket.slug}:{plan.file}
		</div>
	),
}));

import { TicketDndProvider, usePlanDraggable, useTicketDrag, useTicketDropTarget } from "./TicketDndProvider";

const ticket: TicketWithProject = {
	projectId: "p1",
	projectName: "app",
	slug: "search-page",
	title: "Search page",
	status: "ready",
	plans: [],
	files: [],
};
const plan: PlanView = { file: "plans/01-index.md", order: 1, title: "Index", status: "todo" };

function Handle({ enabled = true }: { enabled?: boolean }) {
	const { attributes, listeners, setNodeRef, setActivatorNodeRef } = usePlanDraggable({ ticket, plan }, enabled);
	return (
		<div ref={setNodeRef}>
			<button ref={setActivatorNodeRef} type="button" {...attributes} {...listeners}>
				handle
			</button>
		</div>
	);
}

function Target({ id }: { id: string }) {
	const { setNodeRef, accepts, isOver, dragging } = useTicketDropTarget(id);
	return <div ref={setNodeRef} data-testid={id} data-accepts={accepts} data-over={isOver} data-dragging={dragging} />;
}

function AssignButton() {
	const { requestAssign } = useTicketDrag();
	return (
		<button type="button" onClick={() => requestAssign(ticket, plan)}>
			assign
		</button>
	);
}

beforeAll(() => {
	if (!Element.prototype.scrollIntoView) Element.prototype.scrollIntoView = () => undefined;
});

beforeEach(() => {
	vi.useRealTimers();
});

describe("TicketDndProvider", () => {
	it("opens the assign sheet from requestAssign without any drag", async () => {
		render(
			<TicketDndProvider>
				<AssignButton />
			</TicketDndProvider>,
		);
		await userEvent.click(screen.getByRole("button", { name: "assign" }));
		expect(screen.getByTestId("assign-sheet")).toHaveTextContent("search-page:plans/01-index.md");
	});

	it("is inert outside the provider", async () => {
		render(
			<>
				<AssignButton />
				<Target id={LANE_DROP_ID} />
			</>,
		);
		await userEvent.click(screen.getByRole("button", { name: "assign" }));
		expect(screen.queryByTestId("assign-sheet")).not.toBeInTheDocument();
		expect(screen.getByTestId(LANE_DROP_ID)).toHaveAttribute("data-dragging", "false");
	});

	it("marks accepting targets during a keyboard drag and opens the sheet on drop", async () => {
		render(
			<TicketDndProvider>
				<Handle />
				<Target id={LANE_DROP_ID} />
				<Target id={projectDropId("p2")} />
			</TicketDndProvider>,
		);
		const handle = screen.getByRole("button", { name: "handle" });
		handle.focus();

		fireEvent.keyDown(handle, { code: "Space", key: " " });
		await act(async () => {
			await new Promise((resolve) => setTimeout(resolve, 0));
		});

		expect(screen.getByTestId(LANE_DROP_ID)).toHaveAttribute("data-dragging", "true");
		expect(screen.getByTestId(LANE_DROP_ID)).toHaveAttribute("data-accepts", "true");
		expect(screen.getByTestId(projectDropId("p2"))).toHaveAttribute("data-accepts", "false");

		fireEvent.keyDown(handle, { code: "ArrowRight", key: "ArrowRight" });
		fireEvent.keyDown(handle, { code: "Space", key: " " });

		expect(await screen.findByTestId("assign-sheet")).toHaveTextContent("plans/01-index.md");
		expect(screen.getByTestId(LANE_DROP_ID)).toHaveAttribute("data-dragging", "false");
	});

	it("does not start a drag from a disabled handle", async () => {
		render(
			<TicketDndProvider>
				<Handle enabled={false} />
				<Target id={LANE_DROP_ID} />
			</TicketDndProvider>,
		);
		const handle = screen.getByRole("button", { name: "handle" });
		fireEvent.keyDown(handle, { code: "Space", key: " " });
		await act(async () => {
			await new Promise((resolve) => setTimeout(resolve, 0));
		});
		expect(screen.getByTestId(LANE_DROP_ID)).toHaveAttribute("data-dragging", "false");
	});
});
