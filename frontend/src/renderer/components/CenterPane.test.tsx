import { fireEvent, render, screen, within } from "@testing-library/react";
import type { ComponentProps } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { AgentSwitch } from "../hooks/useAgentSwitches";
import type { SwitchAgentInput } from "../hooks/useSwitchAgent";
import type { WorkspaceSession } from "../types/workspace";
import { CenterPane } from "./CenterPane";
import { TooltipProvider } from "./ui/tooltip";

const agentSwitchMocks = vi.hoisted(() => ({
	refetch: vi.fn(),
	switches: [] as AgentSwitch[],
	mutation: {
		error: null as string | null,
		input: undefined as SwitchAgentInput | undefined,
		isPending: false,
	},
}));

vi.mock("../hooks/useAgentSwitches", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../hooks/useAgentSwitches")>();
	return {
		...actual,
		useAgentSwitches: () => ({ data: agentSwitchMocks.switches, refetch: agentSwitchMocks.refetch }),
	};
});

vi.mock("../hooks/useSwitchAgent", () => ({
	useSwitchAgentState: () => agentSwitchMocks.mutation,
}));

vi.mock("./TerminalSwitchAgentButton", () => ({
	TerminalSwitchAgentButton: ({ session }: { session: WorkspaceSession }) => (
		<button aria-label="Switch agent" data-testid="terminal-switch-agent" type="button">
			{session.provider}
		</button>
	),
}));

vi.mock("../lib/bridge", () => ({
	operatorBridge: {
		app: {},
		clipboard: { writeText: vi.fn() },
	},
}));

// The terminal body pulls in xterm/SSE machinery irrelevant to the header under test.
const cacheMocks = vi.hoisted(() => ({ releaseWorker: vi.fn() }));

vi.mock("./TerminalPane", () => ({
	TerminalPane: ({ focusRequested }: { focusRequested?: boolean }) => (
		<div data-focus-requested={focusRequested ? "true" : "false"}>terminal body</div>
	),
	useTerminalCacheController: () => ({
		activate: vi.fn(),
		deactivate: vi.fn(),
		update: vi.fn(),
		releaseWorker: cacheMocks.releaseWorker,
	}),
}));

const worker = {
	id: "sess-1",
	workspaceId: "proj-1",
	workspaceName: "my-app",
	title: "do the thing",
	provider: "claude-code",
	kind: "worker",
	branch: "opr/sess-1",
	status: "working",
	updatedAt: "2026-06-10T00:00:00Z",
	activity: { state: "active", lastActivityAt: "2026-06-10T00:00:00Z" },
	prs: [],
} satisfies WorkspaceSession;

function renderCenterPane(props: Partial<ComponentProps<typeof CenterPane>> = {}) {
	return render(
		<TooltipProvider>
			<CenterPane daemonReady theme="dark" {...props} />
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
	cacheMocks.releaseWorker.mockReset();
});

describe("CenterPane toolbar session label", () => {
	it("shows the session display name for a worker", () => {
		renderCenterPane({ session: worker });
		expect(screen.getByText("do the thing")).toBeInTheDocument();
		expect(screen.queryByText("sess-1")).not.toBeInTheDocument();
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

		renderCenterPane({ session: worker });

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

		renderCenterPane({
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
		expect(screen.queryByRole("button", { name: "Cancel switch" })).not.toBeInTheDocument();
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

		renderCenterPane({
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

	it("renders only this session's own tab, never a sibling session", () => {
		renderCenterPane({ session: worker });

		const sessionTab = screen.getByRole("tab", { name: /^do the thing/ });
		expect(sessionTab).toHaveAttribute("aria-selected", "true");
		expect(sessionTab.parentElement).toHaveClass(
			"self-stretch",
			"bg-overlay",
			"after:h-0.5",
			"after:bg-foreground/80",
		);
		expect(sessionTab.parentElement).not.toHaveClass("session-primary-tab");
		expect(sessionTab.parentElement).not.toHaveClass("rounded-md");
		expect(sessionTab).toHaveAccessibleName("do the thing · Working");
		expect(sessionTab.querySelector('[title="Working"]')).toBeInTheDocument();
		expect(sessionTab.parentElement?.querySelector('img[aria-hidden="true"]')).toBeInTheDocument();
		expect(screen.queryByRole("tab", { name: "review the change" })).not.toBeInTheDocument();
	});

	it("shows reviewer as its own active harness tab", () => {
		renderCenterPane({
			session: worker,
			reviewerTerminal: { handleId: "review-sess-1", harness: "codex" },
			terminalTarget: { kind: "reviewer", handleId: "review-sess-1", harness: "codex", sessionId: worker.id },
		});

		expect(screen.getByRole("tab", { name: "Reviewer" })).toHaveAttribute("aria-current", "true");
		expect(screen.getByRole("tab", { name: /^do the thing/ })).not.toHaveAttribute("aria-current", "true");
		expect(screen.getByRole("tab", { name: "Reviewer" }).querySelector("img")).toHaveAttribute("src");
		expect(screen.queryByRole("button", { name: "Back to agent" })).not.toBeInTheDocument();
	});

	it("opens reviewer from the tab strip when a reviewer handle exists", () => {
		const onSelectReviewerTerminal = vi.fn();
		renderCenterPane({
			session: worker,
			reviewerTerminal: { handleId: "review-sess-1", harness: "codex" },
			onSelectReviewerTerminal,
		});

		fireEvent.click(screen.getByRole("tab", { name: "Reviewer" }));
		expect(onSelectReviewerTerminal).toHaveBeenCalledWith({ handleId: "review-sess-1", harness: "codex" });
	});

	it("shows 'Orchestrator' for an orchestrator session", () => {
		renderCenterPane({
			session: { ...worker, id: "sess-orch", kind: "orchestrator" },
		});
		expect(screen.getByText("Orchestrator")).toBeInTheDocument();
	});

	it("shows 'No session' when there is no session", () => {
		renderCenterPane();
		expect(screen.getByText("No session")).toBeInTheDocument();
	});

	it("uses the inspector tab height for the terminal header", () => {
		renderCenterPane({ session: worker });

		const tablist = screen.getByRole("tablist", { name: "Open terminals" });
		const header = tablist.closest(".h-inspector-tabs");
		expect(header).toHaveClass("h-inspector-tabs");
		expect(tablist.parentElement).toHaveClass("h-full");
	});

	it("keeps terminal controls in the measured terminal region and session actions outside it", () => {
		renderCenterPane({
			session: worker,
			topbarActions: <button type="button">Session action</button>,
		});

		const terminalRegion = screen.getByTestId("session-terminal-region");
		const workspaceTopbar = screen.getByTestId("session-workspace-topbar");
		expect(workspaceTopbar).toHaveClass("session-topbar-surface");
		expect(workspaceTopbar).toContainElement(terminalRegion);
		expect(terminalRegion).toContainElement(screen.getByRole("tablist", { name: "Open terminals" }));
		expect(terminalRegion).not.toContainElement(screen.getByTestId("session-action-region"));
		const actionRegion = screen.getByTestId("session-action-region");
		expect(actionRegion).not.toHaveClass("border-l");
		expect(actionRegion).toContainElement(
			screen.getByRole("button", { name: "Session action" }),
		);
	});

	// The font-size stepper and the fullscreen button are gone; the topbar is the
	// tab strip and the session actions.
	it("offers no font-size or fullscreen controls", () => {
		renderCenterPane({ session: worker, topbarActions: <button type="button">Session action</button> });

		expect(screen.queryByRole("toolbar", { name: /display controls/i })).not.toBeInTheDocument();
		expect(screen.queryByRole("button", { name: /font size/i })).not.toBeInTheDocument();
		expect(screen.queryByRole("button", { name: /fullscreen/i })).not.toBeInTheDocument();
		expect(screen.getByTestId("session-action-region")).toBeInTheDocument();
	});

	it("does not reserve tab-strip space for unavailable overflow controls", () => {
		renderCenterPane({ session: worker });

		expect(screen.getByTestId("session-terminal-region")).not.toHaveClass("pl-0.5");
		expect(screen.getByRole("tablist", { name: "Open terminals" })).not.toHaveClass("pt-1.5");
		expect(screen.queryByRole("button", { name: "Scroll tabs left" })).not.toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Scroll tabs right" })).not.toBeInTheDocument();
	});

	it("reveals scroll chevrons only when the tab strip actually overflows", () => {
		renderCenterPane({ session: worker });

		const scrollRegion = document.querySelector(".overflow-x-auto") as HTMLElement;
		Object.defineProperty(scrollRegion, "clientWidth", {
			value: 100,
			configurable: true,
		});
		Object.defineProperty(scrollRegion, "scrollWidth", {
			value: 500,
			configurable: true,
		});
		fireEvent.scroll(scrollRegion);

		expect(screen.getByRole("button", { name: "Scroll tabs right" })).toBeEnabled();
		expect(screen.queryByRole("button", { name: "Scroll tabs left" })).not.toBeInTheDocument();

		Object.defineProperty(scrollRegion, "scrollLeft", {
			value: 400,
			configurable: true,
		});
		fireEvent.scroll(scrollRegion);
		expect(screen.getByRole("button", { name: "Scroll tabs left" })).toBeEnabled();
		expect(screen.queryByRole("button", { name: "Scroll tabs right" })).not.toBeInTheDocument();
	});

	it("scrolls the tab strip horizontally with the mouse wheel", () => {
		renderCenterPane({ session: worker });

		const scrollRegion = document.querySelector(".overflow-x-auto") as HTMLElement;
		Object.defineProperty(scrollRegion, "clientWidth", {
			value: 100,
			configurable: true,
		});
		Object.defineProperty(scrollRegion, "scrollWidth", {
			value: 500,
			configurable: true,
		});
		const scrollBy = vi.fn();
		Object.defineProperty(scrollRegion, "scrollBy", {
			value: scrollBy,
			configurable: true,
		});

		fireEvent.wheel(scrollRegion, { deltaY: 80 });
		expect(scrollBy).toHaveBeenCalledWith({ left: 80 });

		// Ctrl+wheel is terminal font zoom, not tab scrolling.
		scrollBy.mockClear();
		fireEvent.wheel(scrollRegion, { deltaY: 80, ctrlKey: true });
		expect(scrollBy).not.toHaveBeenCalled();
	});

});

describe("CenterPane surfaces", () => {
	const tuiWorker = worker;

	// The pane is the raw terminal, full stop. Blocks were a third surface
	// alongside it and the chat UI; the toggle and the mode it stored are gone.
	it("renders the terminal for every target, with no blocks toggle", () => {
		const { unmount } = renderCenterPane({ session: tuiWorker });
		expect(screen.getByText("terminal body")).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: /blocks/i })).not.toBeInTheDocument();
		unmount();

		renderCenterPane({
			session: tuiWorker,
			terminalTarget: { kind: "shell", generation: "0", handleId: "h-0", sessionId: "sess-1", title: "operator-0" },
		});
		expect(screen.getByText("terminal body")).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: /blocks/i })).not.toBeInTheDocument();
	});
});
