import { describe, expect, it } from "vitest";
import type { WorkspaceSession } from "../types/workspace";
import { claudeAccountLabelForSession, sharedClaudeLogins, type ClaudeAccount } from "./useClaudeAccounts";

const session = (overrides: Partial<WorkspaceSession> = {}): WorkspaceSession => ({
	id: "sess-1",
	workspaceId: "proj-1",
	workspaceName: "my-app",
	title: "do the thing",
	provider: "claude-code",
	status: "working",
	updatedAt: "2026-06-10T00:00:00Z",
	prs: [],
	...overrides,
});

const account = (id: string, label: string): ClaudeAccount => ({
	id,
	label,
	configDir: `/home/${id}`,
	isDefault: id === "default",
	isPreferred: false,
	sharedSetup: null,
	status: { loggedIn: true },
});

describe("claudeAccountLabelForSession", () => {
	it("returns nothing for non-Claude sessions", () => {
		expect(claudeAccountLabelForSession(session({ provider: "codex", claudeAccountId: "personal" }), [])).toBeUndefined();
	});

	it("names the matching account", () => {
		const accounts = [account("default", "Work"), account("personal", "Personal Pro")];
		expect(claudeAccountLabelForSession(session({ claudeAccountId: "personal" }), accounts)).toBe("Personal Pro");
	});

	it("treats a missing id as the default account", () => {
		expect(claudeAccountLabelForSession(session(), [account("default", "Work")])).toBe("Work");
		expect(claudeAccountLabelForSession(session({ claudeAccountId: "  " }), [account("default", "Work")])).toBe("Work");
	});

	it("falls back to the capitalized id when the account is unknown", () => {
		expect(claudeAccountLabelForSession(session({ claudeAccountId: "personal" }), undefined)).toBe("Personal");
		expect(claudeAccountLabelForSession(session(), [])).toBe("Default");
	});
});

describe("sharedClaudeLogins", () => {
	const account = (id: string, label: string, status: Record<string, unknown>) =>
		({ id, label, configDir: `/u/.claude-${id}`, isDefault: id === "default", isPreferred: false, status, sharedSetup: {} }) as ClaudeAccount;

	it("groups accounts whose probe reports the same email and org", () => {
		const shared = sharedClaudeLogins([
			account("default", "Default", { loggedIn: true, reportedEmail: "a@b.c", reportedOrgId: "org-1" }),
			account("personal", "Personal", { loggedIn: true, reportedEmail: "a@b.c", reportedOrgId: "org-1" }),
			account("work", "Work", { loggedIn: true, reportedEmail: "w@b.c", reportedOrgId: "org-2" }),
		]);
		expect(shared.get("default")).toEqual(["Personal"]);
		expect(shared.get("personal")).toEqual(["Default"]);
		expect(shared.has("work")).toBe(false);
	});

	it("treats the same email in different orgs as different logins", () => {
		const shared = sharedClaudeLogins([
			account("default", "Default", { loggedIn: true, reportedEmail: "a@b.c", reportedOrgId: "org-1" }),
			account("team", "Team", { loggedIn: true, reportedEmail: "a@b.c", reportedOrgId: "org-2" }),
		]);
		expect(shared.size).toBe(0);
	});

	it("ignores accounts without a reported email", () => {
		const shared = sharedClaudeLogins([
			account("default", "Default", { loggedIn: true }),
			account("personal", "Personal", { loggedIn: false }),
			account("other", "Other", { loggedIn: true, reportedEmail: "" }),
		]);
		expect(shared.size).toBe(0);
	});
});
