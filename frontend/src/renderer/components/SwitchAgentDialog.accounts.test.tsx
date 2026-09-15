import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, expect, test, vi } from "vitest";

const accounts = [
	{ id: "default", label: "Default", configDir: "/Users/u/.claude", isDefault: true, status: { loggedIn: true, subscriptionType: "max" }, sharedSetup: {} },
	{ id: "personal", label: "Personal", configDir: "/Users/u/.claude-personal", isDefault: false, status: { loggedIn: true, subscriptionType: "pro" }, sharedSetup: {} },
];

const h = vi.hoisted(() => ({ mutate: vi.fn(), accounts: undefined as unknown[] | undefined }));

vi.mock("../hooks/useClaudeAccounts", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../hooks/useClaudeAccounts")>();
	return { ...actual, useClaudeAccounts: () => ({ data: h.accounts, isPending: h.accounts === undefined }) };
});

vi.mock("../hooks/useSwitchAgent", () => ({
	createSwitchAgentIdempotencyKey: () => "key-1",
	clearSwitchAgentState: vi.fn(),
	useSwitchAgent: () => ({ mutate: h.mutate }),
	useSwitchAgentState: () => ({ isPending: false, input: undefined, error: null }),
}));

vi.mock("../hooks/useAgentSwitches", () => ({
	findActiveAgentSwitch: () => undefined,
	findRecoveryRequiredAgentSwitch: () => undefined,
	isTerminalAgentSwitch: () => false,
	useAgentSwitches: () => ({ data: [], isPending: false, error: null }),
}));

vi.mock("@tanstack/react-query", async (importOriginal) => {
	const actual = await importOriginal<typeof import("@tanstack/react-query")>();
	return { ...actual, useQueryClient: () => ({}) };
});

import { SwitchAgentDialog } from "./SwitchAgentDialog";

const session = {
	id: "s-1",
	workspaceId: "p",
	workspaceName: "P",
	title: "t",
	provider: "claude-code",
	claudeAccountId: "default",
	status: "working",
	updatedAt: "2026-09-14T00:00:00Z",
} as never;

beforeEach(() => {
	h.mutate.mockReset();
	h.accounts = accounts;
});

test("a Claude session defaults to Claude on its other account", async () => {
	render(<SwitchAgentDialog open session={session} onOpenChange={vi.fn()} />);
	expect(screen.getByRole("combobox", { name: "Claude account" })).toBeInTheDocument();
	await userEvent.click(screen.getByRole("button", { name: /Switch/ }));
	expect(h.mutate).toHaveBeenCalledWith(
		expect.objectContaining({ targetHarness: "claude-code", targetClaudeAccountId: "personal" }),
	);
});

test("the target form waits for the accounts instead of flipping its default", async () => {
	h.accounts = undefined;
	const { rerender } = render(<SwitchAgentDialog open session={session} onOpenChange={vi.fn()} />);
	expect(screen.queryByRole("combobox", { name: "Target agent" })).toBeNull();
	expect(screen.queryByRole("button", { name: /Switch/ })).toBeNull();
	h.accounts = accounts;
	rerender(<SwitchAgentDialog open session={session} onOpenChange={vi.fn()} />);
	expect(screen.getByRole("combobox", { name: "Target agent" })).toHaveTextContent("Claude Code");
	await userEvent.click(screen.getByRole("button", { name: /Switch/ }));
	expect(h.mutate).toHaveBeenCalledWith(expect.objectContaining({ targetHarness: "claude-code", targetClaudeAccountId: "personal" }));
});
