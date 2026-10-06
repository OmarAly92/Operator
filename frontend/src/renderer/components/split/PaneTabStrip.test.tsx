import { DndContext } from "@dnd-kit/core";
import { fireEvent, render, screen } from "@testing-library/react";
import type { ComponentProps } from "react";
import { describe, expect, it, vi } from "vitest";
import type { Pane, TabRef } from "../../lib/split-layout";
import type { ShellTerminal } from "../../hooks/useShellTerminals";
import type { WorkspaceSession } from "../../types/workspace";
import { TooltipProvider } from "../ui/tooltip";
import { PaneTabStrip } from "./PaneTabStrip";

const relaunchMocks = vi.hoisted(() => ({ mutateAsync: vi.fn(), isPending: false }));
const claudeAccountsMock = vi.hoisted(() => ({ accounts: [] as unknown[] }));

vi.mock("../../hooks/useRelaunchAgent", () => ({
	useRelaunchAgent: () => ({ mutateAsync: relaunchMocks.mutateAsync, isPending: relaunchMocks.isPending }),
	useRelaunchAgentPending: () => relaunchMocks.isPending,
}));

vi.mock("../../hooks/useClaudeAccounts", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../hooks/useClaudeAccounts")>();
	return { ...actual, useClaudeAccounts: () => ({ data: claudeAccountsMock.accounts }) };
});

vi.mock("../../hooks/useSwitchAgentAction", () => ({
	useSwitchAgentAction: () => ({
		available: true,
		label: "Switch agent",
		recovery: false,
		switching: false,
		open: vi.fn(),
		dialog: null,
	}),
}));

const a: WorkspaceSession = {
	id: "a",
	workspaceId: "p",
	workspaceName: "app",
	title: "alpha",
	provider: "claude-code",
	status: "working",
	updatedAt: "2026-09-22T00:00:00Z",
	prs: [],
};
const shell: ShellTerminal = { handleId: "h1", sessionId: "a", workingDir: "/tmp", title: "zsh", createdAt: "2026-09-22T00:00:00Z" };
const pane: Pane = {
	type: "pane",
	id: "p1",
	tabs: [
		{ kind: "session", sessionId: "a" },
		{ kind: "shell", handleId: "h1", sessionId: "a" },
	],
	activeTab: 0,
};

function renderStrip(overrides: Partial<ComponentProps<typeof PaneTabStrip>> = {}) {
	return render(
		<TooltipProvider>
			<DndContext>
				<PaneTabStrip
					onClose={vi.fn()}
					onRenameShell={vi.fn()}
					onSelect={vi.fn()}
					pane={pane}
					sessions={new Map([["a", a]])}
					shells={new Map([["h1", shell]])}
					{...overrides}
				/>
			</DndContext>
		</TooltipProvider>,
	);
}

describe("PaneTabStrip", () => {
	it("renders a draggable tab per TabRef and routes select and close", () => {
		const onSelect = vi.fn();
		const onClose = vi.fn();
		renderStrip({ pane, onSelect, onClose });
		expect(document.querySelectorAll("[data-split-tab]")).toHaveLength(2);
		expect(screen.getByRole("tab", { name: /alpha/ })).toHaveAttribute("aria-selected", "true");
		fireEvent.click(screen.getByRole("tab", { name: "zsh" }));
		expect(onSelect).toHaveBeenCalledWith(pane.tabs[1]);
		fireEvent.click(screen.getByRole("button", { name: "Close alpha" }));
		expect(onClose).toHaveBeenCalledWith(pane.tabs[0]);
	});

	it("labels a tab whose session is gone as having no session", () => {
		renderStrip({ pane: { ...pane, tabs: [{ kind: "session", sessionId: "gone" }] } });
		expect(screen.getByRole("tab", { name: "No session" })).toBeInTheDocument();
	});

	it("gives a reviewer tab a close button that routes through onClose", () => {
		const onClose = vi.fn();
		const reviewerTab: TabRef = { kind: "reviewer", sessionId: "a", handleId: "r1", harness: "codex" };
		renderStrip({ pane: { ...pane, tabs: [reviewerTab], activeTab: 0 }, onClose });
		fireEvent.click(screen.getByRole("button", { name: "Close Reviewer" }));
		expect(onClose).toHaveBeenCalledWith(reviewerTab);
	});

	it("does not intercept Enter/Space bubbling up from a tab, so no phantom drag starts", () => {
		renderStrip();
		const tab = screen.getByRole("tab", { name: "zsh" });
		expect(fireEvent.keyDown(tab, { key: "Enter", code: "Enter" })).toBe(true);
		expect(fireEvent.keyDown(tab, { key: " ", code: "Space" })).toBe(true);
		expect(tab.closest("[data-split-tab]")?.className).not.toContain("opacity-50");
	});

	it("lets a shell rename gain focus, accept a space, and commit with Enter without starting a drag", async () => {
		renderStrip();
		fireEvent.doubleClick(screen.getByRole("tab", { name: "zsh" }));
		const input = await screen.findByLabelText("Rename terminal zsh");
		fireEvent.change(input, { target: { value: "new zsh" } });
		expect(input).toHaveValue("new zsh");
		expect(input.closest("[data-split-tab]")?.className).not.toContain("opacity-50");
		fireEvent.keyDown(input, { key: "Enter" });
		expect(screen.queryByLabelText("Rename terminal zsh")).not.toBeInTheDocument();
	});

	it("hides the new-tab button when the pane has no project", () => {
		renderStrip();
		expect(screen.queryByRole("button", { name: "New tab" })).not.toBeInTheDocument();
	});

	it("opens a new-tab menu offering a new session and a project terminal", async () => {
		const onNewSession = vi.fn();
		const onNewTerminal = vi.fn();
		renderStrip({ onNewSession, onNewTerminal });
		const trigger = screen.getByRole("button", { name: "New tab" });
		fireEvent.pointerDown(trigger, { button: 0, ctrlKey: false, pointerType: "mouse" });
		fireEvent.click(await screen.findByRole("menuitem", { name: "New session" }));
		expect(onNewSession).toHaveBeenCalledTimes(1);
		fireEvent.pointerDown(trigger, { button: 0, ctrlKey: false, pointerType: "mouse" });
		fireEvent.click(await screen.findByRole("menuitem", { name: "Open terminal" }));
		expect(onNewTerminal).toHaveBeenCalledTimes(1);
	});
});
