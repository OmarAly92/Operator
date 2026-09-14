import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { expect, test, vi } from "vitest";
import { ClaudeAccountSelect } from "./ClaudeAccountSelect";

const accounts = [
	{ id: "default", label: "Default", configDir: "/Users/u/.claude", isDefault: true, status: { loggedIn: true, subscriptionType: "max" }, sharedSetup: {} },
	{ id: "personal", label: "Personal", configDir: "/Users/u/.claude-personal", isDefault: false, status: { loggedIn: false }, sharedSetup: {} },
];

test("shows each account with its plan and reports the chosen id", async () => {
	const onChange = vi.fn();
	render(<ClaudeAccountSelect id="acct" ariaLabel="Account" value="default" onChange={onChange} accounts={accounts} />);
	await userEvent.click(screen.getByRole("combobox", { name: "Account" }));
	expect(await screen.findByRole("option", { name: "Personal · Not logged in" })).toBeInTheDocument();
	await userEvent.click(screen.getByRole("option", { name: "Personal · Not logged in" }));
	expect(onChange).toHaveBeenCalledWith("personal");
});
