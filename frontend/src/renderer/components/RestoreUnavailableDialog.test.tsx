import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import type { WorkspaceSession } from "../types/workspace";
import { RestoreUnavailableDialog } from "./RestoreUnavailableDialog";

const session: WorkspaceSession = {
	id: "sess-1",
	workspaceId: "proj-1",
	workspaceName: "Project One",
	title: "fix the bug",
	provider: "codex",
	status: "terminated",
	updatedAt: "2026-07-26T00:00:00Z",
	prs: [],
};

describe("RestoreUnavailableDialog", () => {
	it("closes without recreating when the session cannot be restored", async () => {
		const onOpenChange = vi.fn();
		const onRecreated = vi.fn();
		render(
			<RestoreUnavailableDialog open session={session} onOpenChange={onOpenChange} onRecreated={onRecreated} />,
		);

		expect(screen.getByText("Session can no longer be restored")).toBeInTheDocument();
		const closeButtons = screen.getAllByRole("button", { name: "Close" });
		await userEvent.click(closeButtons[closeButtons.length - 1]);

		expect(onOpenChange).toHaveBeenCalledWith(false);
		expect(onRecreated).not.toHaveBeenCalled();
	});
});
