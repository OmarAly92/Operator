import { render } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { terminalShownInAPane } from "../lib/on-screen-terminals";
import { useUiStore } from "../stores/ui-store";
import { ShellTerminalsView } from "./ShellTerminalsView";

vi.mock("../hooks/useShellTerminals", () => ({
	useCloseShellTerminal: () => ({ mutate: vi.fn() }),
	useRenameShellTerminal: () => ({ mutate: vi.fn() }),
	useShellTerminals: () => ({ data: [{ handleId: "shell-a", workingDir: "/tmp", title: "zsh", createdAt: "now" }] }),
}));

vi.mock("../lib/shell-context", () => ({
	useShell: () => ({ daemonStatus: { state: "ready" } }),
}));

vi.mock("./TerminalPane", () => ({ TerminalPane: () => <div>terminal body</div> }));

describe("ShellTerminalsView on-screen terminal", () => {
	it("claims the active shell while shown and releases it on unmount", () => {
		useUiStore.getState().setActiveShellTerminal("shell-a");
		const { unmount } = render(<ShellTerminalsView />);
		expect(terminalShownInAPane("shell-a")).toBe(true);
		unmount();
		expect(terminalShownInAPane("shell-a")).toBe(false);
	});
});
