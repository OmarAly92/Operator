import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, fireEvent, render, screen } from "@testing-library/react";
import type { ComponentProps } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Pane } from "../../lib/split-layout";
import type { ShellTerminal } from "../../hooks/useShellTerminals";
import type { WorkspaceSession } from "../../types/workspace";
import { TooltipProvider } from "../ui/tooltip";
import { clearTerminalTitles, setTerminalTitle } from "../../lib/terminal-titles";
import { SplitPane } from "./SplitPane";

vi.mock("./PaneTerminal", async (importOriginal) => {
	const actual = await importOriginal<typeof import("./PaneTerminal")>();
	return {
		...actual,
		PaneTerminal: ({ focused, target }: { focused: boolean; target: { kind: string } }) => (
			<div data-focused={String(focused)} data-target={target.kind} data-testid="pane-terminal" />
		),
	};
});

vi.mock("./PaneTabStrip", () => ({
	PaneTabStrip: () => <div data-testid="pane-tab-strip" />,
}));

const a: WorkspaceSession = {
	id: "a",
	workspaceId: "p",
	workspaceName: "app",
	title: "alpha",
	terminalHandleId: "ha",
	provider: "claude-code",
	status: "working",
	updatedAt: "2026-09-22T00:00:00Z",
	prs: [],
};
const shell: ShellTerminal = { handleId: "h1", sessionId: "a", workingDir: "/tmp", title: "zsh", createdAt: "2026-09-22T00:00:00Z" };
const basePane: Pane = {
	type: "pane",
	id: "p1",
	tabs: [
		{ kind: "session", sessionId: "a" },
		{ kind: "shell", handleId: "h1", sessionId: "a" },
	],
	activeTab: 0,
};

const queryClient = new QueryClient();

function paneTree(overrides: Partial<ComponentProps<typeof SplitPane>> = {}) {
	return (
		<QueryClientProvider client={queryClient}>
			<TooltipProvider>
				<SplitPane
					daemonReady
					focused
					onClose={vi.fn()}
					onClosePane={vi.fn()}
					onFocus={vi.fn()}
					onRenameShell={vi.fn()}
					onSelect={vi.fn()}
					pane={basePane}
					sessions={new Map([["a", a]])}
					shells={new Map([["h1", shell]])}
					showFocusRing={false}
					theme="dark"
					topLeft={false}
					touchesTop={false}
					{...overrides}
				/>
			</TooltipProvider>
		</QueryClientProvider>
	);
}

function renderPane(overrides: Partial<ComponentProps<typeof SplitPane>> = {}) {
	return render(paneTree(overrides));
}

afterEach(() => clearTerminalTitles());

describe("SplitPane", () => {
	it("focuses on pointer down, renders the ring only when asked, and closes the pane", () => {
		const onFocus = vi.fn();
		const onClosePane = vi.fn();
		const { rerender } = renderPane({ onFocus, onClosePane, showFocusRing: false });
		fireEvent.pointerDown(screen.getByTestId("pane-terminal"));
		expect(onFocus).toHaveBeenCalled();
		expect(document.querySelector(".border-ring\\/60")).toBeNull();
		rerender(paneTree({ onFocus, onClosePane, showFocusRing: true }));
		expect(document.querySelector(".border-ring\\/60")).not.toBeNull();
		fireEvent.click(screen.getByRole("button", { name: "Close pane" }));
		expect(onClosePane).toHaveBeenCalled();
	});

	it("shows the active tab's terminal title in the pane header", () => {
		act(() => {
			setTerminalTitle("ha", "Number list 1 to 3000");
			setTerminalTitle("h1", "vim main.go");
		});
		const { rerender } = renderPane();
		const title = screen.getByTestId("pane-terminal-title");
		expect(title).toHaveTextContent("Number list 1 to 3000");
		expect(title).toHaveAccessibleName("Terminal title: Number list 1 to 3000");
		rerender(paneTree({ pane: { ...basePane, activeTab: 1 } }));
		expect(screen.getByTestId("pane-terminal-title")).toHaveTextContent("vim main.go");
		act(() => setTerminalTitle("h1", ""));
		expect(screen.queryByTestId("pane-terminal-title")).toBeNull();
	});

	it("hands the active tab's target to the terminal", () => {
		renderPane({ pane: { ...basePane, activeTab: 1 } });
		expect(screen.getByTestId("pane-terminal")).toHaveAttribute("data-target", "shell");
	});
});
