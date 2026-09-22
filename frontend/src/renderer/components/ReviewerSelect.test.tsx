import { useState } from "react";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import type { components } from "../../api/schema";
import { ReviewerSelect, reviewerTrustWarning } from "./ReviewerSelect";

type AgentInfo = components["schemas"]["AgentInfo"];
type Catalog = { supported: AgentInfo[]; installed: AgentInfo[]; authorized: AgentInfo[] };

const baseCatalog: Catalog = {
	supported: [
		{ id: "claude-code", label: "Claude Code" },
		{ id: "codex", label: "Codex" },
		{ id: "copilot", label: "GitHub Copilot" },
		{ id: "cursor", label: "Cursor" },
		{ id: "goose", label: "Goose" },
		{ id: "kilocode", label: "Kilo Code" },
		{ id: "kiro", label: "Kiro" },
		{ id: "opencode", label: "OpenCode" },
		{ id: "pi", label: "Pi" },
	],
	installed: [
		{ id: "claude-code", label: "Claude Code", authStatus: "authorized" },
		{ id: "codex", label: "Codex", authStatus: "authorized" },
		{ id: "copilot", label: "GitHub Copilot", authStatus: "authorized" },
		{ id: "cursor", label: "Cursor", authStatus: "authorized" },
		{ id: "goose", label: "Goose", authStatus: "authorized" },
		{ id: "kilocode", label: "Kilo Code", authStatus: "authorized" },
		{ id: "kiro", label: "Kiro", authStatus: "unknown" },
		{ id: "opencode", label: "OpenCode", authStatus: "authorized" },
		{ id: "pi", label: "Pi", authStatus: "authorized" },
	],
	authorized: [
		{ id: "claude-code", label: "Claude Code", authStatus: "authorized" },
		{ id: "codex", label: "Codex", authStatus: "authorized" },
		{ id: "copilot", label: "GitHub Copilot", authStatus: "authorized" },
		{ id: "cursor", label: "Cursor", authStatus: "authorized" },
		{ id: "goose", label: "Goose", authStatus: "authorized" },
		{ id: "kilocode", label: "Kilo Code", authStatus: "authorized" },
		{ id: "opencode", label: "OpenCode", authStatus: "authorized" },
		{ id: "pi", label: "Pi", authStatus: "authorized" },
	],
};

function withAgents(...extra: AgentInfo[]): Catalog {
	return {
		supported: [...baseCatalog.supported, ...extra],
		installed: [...baseCatalog.installed, ...extra],
		authorized: [...baseCatalog.authorized, ...extra],
	};
}

function Harness({ catalog, onChange }: { catalog: Catalog; onChange?: (value: string) => void }) {
	const [value, setValue] = useState("");
	const warning = reviewerTrustWarning(value);
	return (
		<>
			<ReviewerSelect
				value={value}
				onChange={(next) => {
					setValue(next);
					onChange?.(next);
				}}
				defaultOptionLabel="Project default"
				defaultTriggerLabel="Project default"
				authorized={catalog.authorized}
				installed={catalog.installed}
				supported={catalog.supported}
			/>
			{warning ? <p role="status">{warning}</p> : null}
		</>
	);
}

async function openMenu() {
	await userEvent.click(await screen.findByRole("button", { name: "Default reviewer agent" }));
	return screen.findAllByRole("menuitem");
}

describe("ReviewerSelect", () => {
	it("offers both interactive Kiro and Pi reviewers", async () => {
		render(<Harness catalog={baseCatalog} />);
		const labels = (await openMenu()).map((option) => option.textContent);
		expect(labels).toContain("KiroAuth unknown");
		expect(labels).toContain("Pi");
	});

	it("offers Muse Code as a reviewer", async () => {
		render(<Harness catalog={withAgents({ id: "muse", label: "Muse Code", authStatus: "authorized" })} />);
		await openMenu();
		expect(await screen.findByRole("menuitem", { name: /Muse Code/ })).toBeInTheDocument();
	});

	it("orders reviewers using the default agent priority", async () => {
		render(<Harness catalog={baseCatalog} />);
		const labels = (await openMenu())
			.map((option) => option.textContent)
			.filter((label) => label !== "Project default");
		expect(labels).toEqual([
			"Claude Code",
			"Codex",
			"Cursor",
			"OpenCode",
			"GitHub Copilot",
			"Goose",
			"Kilo Code",
			"Pi",
			"KiroAuth unknown",
		]);
	});

	it("offers the experimental host-trusted reviewer set", async () => {
		render(
			<Harness
				catalog={withAgents(
					{ id: "qwen", label: "Qwen Code", authStatus: "authorized" },
					{ id: "devin", label: "Devin", authStatus: "authorized" },
					{ id: "droid", label: "Droid", authStatus: "authorized" },
					{ id: "kimi", label: "Kimi", authStatus: "authorized" },
					{ id: "aider", label: "Aider", authStatus: "authorized" },
					{ id: "amp", label: "Amp", authStatus: "authorized" },
					{ id: "agy", label: "Agy", authStatus: "authorized" },
					{ id: "auggie", label: "Auggie", authStatus: "authorized" },
					{ id: "autohand", label: "Autohand", authStatus: "authorized" },
					{ id: "cline", label: "Cline", authStatus: "authorized" },
					{ id: "continue", label: "Continue", authStatus: "authorized" },
					{ id: "crush", label: "Crush", authStatus: "authorized" },
					{ id: "grok", label: "Grok", authStatus: "authorized" },
					{ id: "vibe", label: "Vibe", authStatus: "authorized" },
				)}
			/>,
		);
		const labels = (await openMenu()).map((option) => option.textContent);
		for (const label of [
			"Qwen Code",
			"Agy",
			"Continue",
			"Goose",
			"Vibe",
			"Devin",
			"Droid",
			"Kimi",
			"Aider",
			"Amp",
			"Auggie",
			"Autohand",
			"Cline",
			"Crush",
			"Grok",
		]) {
			expect(labels).toContain(label);
		}
	});

	it("warns when an experimental reviewer is selected", async () => {
		render(<Harness catalog={withAgents({ id: "kimchi", label: "Kimchi", authStatus: "authorized" })} />);
		await openMenu();
		await userEvent.click(await screen.findByRole("menuitem", { name: /^Kimchi$/i }));
		expect(screen.getByRole("status")).toHaveTextContent("Experimental host-trusted reviewer");
	});

	it("reports the selected Copilot reviewer as enabled", async () => {
		const onChange = vi.fn();
		render(<Harness catalog={baseCatalog} onChange={onChange} />);
		await openMenu();
		const copilot = await screen.findByRole("menuitem", { name: "GitHub Copilot" });
		expect(copilot).not.toHaveAttribute("aria-disabled", "true");
		await userEvent.click(copilot);
		expect(onChange).toHaveBeenCalledWith("copilot");
	});

	it("disables the Copilot reviewer when its binary is missing", async () => {
		render(<Harness catalog={{ supported: [{ id: "copilot", label: "GitHub Copilot" }], installed: [], authorized: [] }} />);
		const copilot = (await openMenu()).find((option) => option.textContent?.includes("GitHub Copilot"));
		expect(copilot).toHaveTextContent("Needs install");
		expect(copilot).toHaveAttribute("aria-disabled", "true");
	});

	it("shows the standard unknown-auth warning for an installed Copilot reviewer", async () => {
		render(
			<Harness
				catalog={{
					supported: [{ id: "copilot", label: "GitHub Copilot" }],
					installed: [{ id: "copilot", label: "GitHub Copilot", authStatus: "unknown" }],
					authorized: [],
				}}
			/>,
		);
		const copilot = (await openMenu()).find((option) => option.textContent?.includes("GitHub Copilot"));
		expect(copilot).toHaveTextContent("Auth unknown");
		expect(copilot).not.toHaveAttribute("aria-disabled", "true");
	});

	it("offers Kilo Code as a configured reviewer", async () => {
		render(<Harness catalog={baseCatalog} />);
		await openMenu();
		expect(await screen.findByRole("menuitem", { name: "Kilo Code" })).toBeEnabled();
	});

	it("offers the experimental Agy reviewer", async () => {
		render(<Harness catalog={withAgents({ id: "agy", label: "Agy", authStatus: "authorized" })} />);
		expect((await openMenu()).map((option) => option.textContent)).toContain("Agy");
	});
});
