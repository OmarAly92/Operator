import { render, screen, within } from "@testing-library/react";
import type { ComponentProps } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { AgentSwitch } from "../../hooks/useAgentSwitches";
import type { SwitchAgentInput } from "../../hooks/useSwitchAgent";
import type { WorkspaceSession } from "../../types/workspace";
import { TooltipProvider } from "../ui/tooltip";
import { PaneTerminal } from "./PaneTerminal";

const agentSwitchMocks = vi.hoisted(() => ({
	refetch: vi.fn(),
	switches: [] as AgentSwitch[],
	mutation: {
		error: null as string | null,
		input: undefined as SwitchAgentInput | undefined,
		isPending: false,
	},
}));

vi.mock("../../hooks/useAgentSwitches", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../hooks/useAgentSwitches")>();
	return {
		...actual,
		useAgentSwitches: () => ({ data: agentSwitchMocks.switches, refetch: agentSwitchMocks.refetch }),
	};
});

vi.mock("../../hooks/useSwitchAgent", () => ({
	useSwitchAgentState: () => agentSwitchMocks.mutation,
}));

vi.mock("../TerminalPane", () => ({
	TerminalPane: ({ focusRequested }: { focusRequested?: boolean }) => (
		<div data-focus-requested={focusRequested ? "true" : "false"}>terminal body</div>
	),
}));

const worker = {
	id: "sess-1",
	workspaceId: "proj-1",
	workspaceName: "my-app",
	title: "do the thing",
	provider: "claude-code",
	branch: "opr/sess-1",
	status: "working",
	updatedAt: "2026-06-10T00:00:00Z",
	activity: { state: "active", lastActivityAt: "2026-06-10T00:00:00Z" },
	prs: [],
} satisfies WorkspaceSession;

function renderPaneTerminal(props: Partial<ComponentProps<typeof PaneTerminal>> = {}) {
	return render(
		<TooltipProvider>
			<PaneTerminal daemonReady focused session={worker} target={{ kind: "worker" }} theme="dark" {...props} />
		</TooltipProvider>,
	);
}

beforeEach(() => {
	agentSwitchMocks.switches.length = 0;
	agentSwitchMocks.refetch.mockReset();
	agentSwitchMocks.refetch.mockResolvedValue(undefined);
	agentSwitchMocks.mutation.error = null;
	agentSwitchMocks.mutation.input = undefined;
	agentSwitchMocks.mutation.isPending = false;
});

describe("PaneTerminal agent-switch overlay", () => {
	it("shows the terminal unlocked with no overlay outside a switch", () => {
		renderPaneTerminal();
		expect(screen.getByText("terminal body")).toBeInTheDocument();
		expect(screen.getByTestId("terminal-interaction-surface")).not.toHaveAttribute("inert");
		expect(screen.queryByTestId("agent-switch-terminal-overlay")).not.toBeInTheDocument();
	});

	it("locks only the terminal and shows the provider transfer as soon as a switch request starts", () => {
		agentSwitchMocks.mutation.input = {
			idempotencyKey: "switch-request-1",
			note: "",
			session: worker,
			targetHarness: "codex",
		};
		agentSwitchMocks.mutation.isPending = true;

		renderPaneTerminal();

		const overlay = screen.getByRole("status", { name: "Switching from Claude Code to Codex" });
		const terminalPanel = screen.getByRole("tabpanel", { name: "do the thing terminal" });
		expect(terminalPanel).toContainElement(overlay);
		expect(screen.getByTestId("terminal-interaction-surface")).toHaveAttribute("inert");
		expect(within(overlay).getByText("Claude Code")).toBeInTheDocument();
		expect(within(overlay).getByText("Codex")).toBeInTheDocument();
		expect(document.activeElement).toBe(screen.getByTestId("agent-switch-terminal-overlay"));
	});

	it("reopens terminal input when the source handoff needs a permission decision", () => {
		agentSwitchMocks.switches.push({
			agentHandoffStatus: "requested",
			fromHarness: "claude-code",
			id: "switch-2",
			requestedAt: "2026-06-10T00:00:00Z",
			semanticHandoffIncluded: true,
			sessionId: worker.id,
			state: "preparing_handoff",
			targetHarness: "codex",
			updatedAt: "2026-06-10T00:00:01Z",
		});

		renderPaneTerminal({
			session: {
				...worker,
				activity: { state: "waiting_input", lastActivityAt: "2026-06-10T00:00:02Z" },
			},
		});

		expect(screen.getByTestId("terminal-interaction-surface")).not.toHaveAttribute("inert");
		expect(screen.getByText("terminal body")).toHaveAttribute("data-focus-requested", "true");
		expect(
			screen.getByText(
				"The source agent requires a permission decision. Review the terminal prompt to continue the handoff.",
			),
		).toBeInTheDocument();
	});

	it("keeps input locked but replaces transfer animation with a recovery warning", () => {
		agentSwitchMocks.switches.push({
			agentHandoffStatus: "unavailable",
			errorCode: "target_start_unconfirmed",
			fromHarness: "claude-code",
			id: "switch-recovery",
			requestedAt: "2026-06-10T00:00:00Z",
			semanticHandoffIncluded: true,
			sessionId: worker.id,
			state: "starting_target",
			targetHarness: "codex",
			updatedAt: "2026-06-10T00:00:01Z",
		});

		renderPaneTerminal({
			session: {
				...worker,
				activity: { state: "exited", lastActivityAt: "2026-06-10T00:00:02Z" },
				status: "exited",
			},
		});

		const overlay = screen.getByRole("alert", { name: "Agent switch needs recovery" });
		expect(screen.getByTestId("terminal-interaction-surface")).toHaveAttribute("inert");
		expect(screen.getByTestId("agent-switch-terminal-overlay")).not.toHaveClass("cursor-wait");
		expect(within(overlay).getByText("Target startup could not be confirmed")).toBeInTheDocument();
		expect(overlay.querySelector(".agent-switch-transfer-pulse")).not.toBeInTheDocument();
	});
});
