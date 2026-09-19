import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

const { accountsMock } = vi.hoisted(() => ({ accountsMock: vi.fn() }));

vi.mock("../../hooks/useClaudeAccounts", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../hooks/useClaudeAccounts")>();
	return { ...actual, useClaudeAccounts: () => accountsMock() };
});

vi.mock("./AgentModelField", () => ({
	AgentModelField: ({ label, model, onModelChange, fieldId }: { label?: string; model: string; onModelChange: (v: string) => void; fieldId?: string }) => (
		<input id={fieldId} aria-label={label} value={model} onChange={(event) => onModelChange(event.target.value)} />
	),
}));

import { cleanTicketDefaults, TicketDefaultsSection } from "./TicketDefaultsSection";

const agents = [
	{ id: "claude-code", label: "Claude Code" },
	{ id: "codex", label: "Codex" },
];

function renderSection(value: Parameters<typeof TicketDefaultsSection>[0]["value"] = {}) {
	const onChange = vi.fn();
	render(
		<QueryClientProvider client={new QueryClient()}>
			<TicketDefaultsSection value={value} onChange={onChange} projectId="p1" fallbackAgent="claude-code" agents={agents} />
		</QueryClientProvider>,
	);
	return onChange;
}

async function chooseOption(trigger: HTMLElement, name: string) {
	await userEvent.click(trigger);
	await userEvent.click(await screen.findByRole("menuitem", { name }));
}

beforeEach(() => {
	accountsMock.mockReset().mockReturnValue({ data: [], isError: false, isLoading: false });
});

describe("TicketDefaultsSection", () => {
	it("renders a row set per role with Project default selected when empty", () => {
		renderSection();
		expect(screen.getByRole("button", { name: "Planner agent" })).toHaveTextContent("Project default");
		expect(screen.getByRole("button", { name: "Implementer agent" })).toHaveTextContent("Project default");
		expect(screen.getByRole("button", { name: "Reviewer agent" })).toHaveTextContent("Project default");
		expect(screen.getByLabelText("Planner model")).toHaveValue("");
		expect(screen.getByRole("radio", { name: "Planning session" })).toHaveAttribute("aria-checked", "true");
		expect(screen.getByRole("switch", { name: "Skip automatic review" })).toHaveAttribute("aria-checked", "false");
	});

	it("emits the changed role, reviewer mode and auto-review switch", async () => {
		const onChange = renderSection({ planner: { agent: "claude-code", model: "claude-opus-5" } });
		expect(screen.getByLabelText("Planner model")).toHaveValue("claude-opus-5");

		await chooseOption(screen.getByRole("button", { name: "Implementer agent" }), "Codex");
		expect(onChange).toHaveBeenLastCalledWith(expect.objectContaining({ implementer: { agent: "codex", model: "", claudeAccountId: "" } }));

		await userEvent.click(screen.getByRole("radio", { name: "New session" }));
		expect(onChange).toHaveBeenLastCalledWith(expect.objectContaining({ reviewerMode: "new" }));

		await userEvent.click(screen.getByRole("switch", { name: "Skip automatic review" }));
		expect(onChange).toHaveBeenLastCalledWith(expect.objectContaining({ disableAutoReview: true }));
	});

	it("shows the account row only for Claude Code with more than one account", () => {
		accountsMock.mockReturnValue({
			data: [
				{ id: "default", label: "Default", isPreferred: true },
				{ id: "personal", label: "Personal" },
			],
			isError: false,
			isLoading: false,
		});
		renderSection({ implementer: { agent: "codex" } });
		expect(screen.getByRole("button", { name: "Planner Claude account" })).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Implementer Claude account" })).not.toBeInTheDocument();
	});
});

describe("cleanTicketDefaults", () => {
	it("drops empty strings, empty roles and returns undefined when nothing is set", () => {
		expect(cleanTicketDefaults({})).toBeUndefined();
		expect(cleanTicketDefaults({ planner: { agent: "", model: "", claudeAccountId: "" }, reviewerMode: undefined })).toBeUndefined();
		expect(
			cleanTicketDefaults({
				planner: { agent: "claude-code", model: " claude-opus-5 ", claudeAccountId: "" },
				implementer: { agent: "", model: "", claudeAccountId: "" },
				reviewerMode: "new",
				disableAutoReview: false,
			}),
		).toEqual({ planner: { agent: "claude-code", model: "claude-opus-5" }, reviewerMode: "new" });
	});
});
