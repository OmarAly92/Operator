import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, expect, test, vi } from "vitest";

const h = vi.hoisted(() => ({
	accounts: [] as unknown[],
	create: vi.fn(),
	login: vi.fn(),
	remove: vi.fn(),
	relink: vi.fn(),
	rename: vi.fn(),
	refresh: vi.fn(),
	closeSettings: vi.fn(),
	setActiveShellTerminal: vi.fn(),
	navigate: vi.fn(),
}));

vi.mock("../../hooks/useClaudeAccounts", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../hooks/useClaudeAccounts")>();
	return {
		...actual,
		useClaudeAccounts: () => ({ data: h.accounts, isPending: false, error: null }),
		useRefreshClaudeAccounts: () => h.refresh,
		useCreateClaudeAccount: () => ({ mutateAsync: h.create, isPending: false }),
		useClaudeAccountLogin: () => ({ mutateAsync: h.login, isPending: false }),
		useDeleteClaudeAccount: () => ({ mutateAsync: h.remove, isPending: false }),
		useRelinkClaudeAccount: () => ({ mutateAsync: h.relink, isPending: false }),
		useRenameClaudeAccount: () => ({ mutateAsync: h.rename, isPending: false }),
	};
});

vi.mock("../../stores/ui-store", () => ({
	useUiStore: (select: (state: unknown) => unknown) =>
		select({ closeSettings: h.closeSettings, setActiveShellTerminal: h.setActiveShellTerminal }),
}));

vi.mock("@tanstack/react-router", () => ({ useNavigate: () => h.navigate }));

import { ClaudeAccountsSection } from "./ClaudeAccountsSection";

beforeEach(() => {
	for (const fn of [h.create, h.login, h.remove, h.relink, h.rename, h.refresh, h.closeSettings, h.setActiveShellTerminal, h.navigate]) {
		fn.mockReset();
	}
	h.accounts = [
		{ id: "default", label: "Default", configDir: "/Users/u/.claude", isDefault: true, status: { loggedIn: true, subscriptionType: "max" }, sharedSetup: {} },
		{
			id: "personal",
			label: "Personal",
			configDir: "/Users/u/.claude-personal",
			isDefault: false,
			status: { loggedIn: false },
			sharedSetup: { "settings.json": "replaced", "CLAUDE.md": "linked" },
		},
	];
});

test("refreshes accounts on mount", () => {
	render(<ClaudeAccountsSection />);
	expect(h.refresh).toHaveBeenCalled();
});

test("lists default first with plan badges and no remove on default", () => {
	render(<ClaudeAccountsSection />);
	const defaultRow = screen.getByTestId("claude-account-default");
	expect(within(defaultRow).getByText("Max")).toBeInTheDocument();
	expect(within(defaultRow).queryByRole("button", { name: "Remove" })).toBeNull();
	const personal = screen.getByTestId("claude-account-personal");
	expect(within(personal).getByText("Not logged in")).toBeInTheDocument();
	expect(within(personal).getByText("/Users/u/.claude-personal")).toBeInTheDocument();
	expect(within(personal).getByText("Setup no longer shared: settings.json")).toBeInTheDocument();
});

test("re-link calls the mutation", async () => {
	h.relink.mockResolvedValue(undefined);
	render(<ClaudeAccountsSection />);
	await userEvent.click(within(screen.getByTestId("claude-account-personal")).getByRole("button", { name: "Re-link" }));
	expect(h.relink).toHaveBeenCalledWith("personal");
});

test("add dialog previews the folder, creates, then opens the login terminal", async () => {
	h.create.mockResolvedValue({ id: "work-2", label: "Work 2" });
	h.login.mockResolvedValue({ handleId: "shellterm-1" });
	render(<ClaudeAccountsSection />);
	await userEvent.click(screen.getByRole("button", { name: "Add account" }));
	await userEvent.type(screen.getByLabelText("Name"), "Work 2");
	expect(screen.getByText("Folder: ~/.claude-work-2")).toBeInTheDocument();
	await userEvent.click(screen.getByRole("button", { name: "Create and log in" }));
	expect(h.create).toHaveBeenCalledWith("Work 2");
	expect(h.login).toHaveBeenCalledWith("work-2");
	expect(h.closeSettings).toHaveBeenCalled();
	expect(h.setActiveShellTerminal).toHaveBeenCalledWith("shellterm-1");
	expect(h.navigate).toHaveBeenCalledWith({ to: "/terminals" });
});

test("remove asks for confirmation and shows the in-use error", async () => {
	h.remove.mockRejectedValue({ code: "CLAUDE_ACCOUNT_IN_USE", message: "Sessions still use this account; remove or switch them first" });
	render(<ClaudeAccountsSection />);
	await userEvent.click(within(screen.getByTestId("claude-account-personal")).getByRole("button", { name: "Remove" }));
	await userEvent.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Remove" }));
	expect(h.remove).toHaveBeenCalledWith("personal");
	expect(await screen.findByText("Sessions still use this account; remove or switch them first")).toBeInTheDocument();
});
