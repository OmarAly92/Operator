import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { WorkspaceSession } from "../../types/workspace";

const LINK = "http://localhost:5173";
const NON_WEB_LINK = "mailto:dev@example.com";

const { openExternalMock } = vi.hoisted(() => ({ openExternalMock: vi.fn() }));

vi.mock("../../lib/external-link-policy", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../lib/external-link-policy")>();
	return {
		...actual,
		openLinkInSystemBrowser: (url: string) => openExternalMock(url),
	};
});

vi.mock("../../hooks/useConversation", () => ({
	useConversation: () => ({
		snapshot: { capabilities: [] },
		isLoading: false,
		unavailable: undefined,
		error: undefined,
		hasOlder: false,
		isLoadingOlder: false,
		loadOlder: vi.fn(),
	}),
	useConversationCommands: () => ({}),
	useConversationConfigOptions: () => ({ options: [] }),
	useConversationModels: () => ({ models: [] }),
	useConversationSkills: () => ({ skills: [] }),
	useStageAttachments: () => undefined,
	useWorkspaceFilePaths: () => ({ paths: [], truncated: false }),
}));

const chatLinkHandlers = { onLinkOpen: undefined as ((url: string) => void) | undefined };

vi.mock("./ChatWorkspace", () => ({
	ChatWorkspace: ({ onLinkOpen }: { onLinkOpen?: (url: string) => void }) => {
		chatLinkHandlers.onLinkOpen = onLinkOpen;
		return (
			<button type="button" onClick={() => onLinkOpen?.(LINK)}>
				Open chat link
			</button>
		);
	},
}));

import { SessionChatSurface } from "./SessionChatSurface";

const session = {
	id: "sess-1",
	workspaceId: "proj-1",
	workspaceName: "my-app",
	title: "chat worker",
	provider: "codex",
	kind: "worker",
	mode: "chat",
	status: "working",
	updatedAt: "2026-08-08T00:00:00Z",
	prs: [],
} satisfies WorkspaceSession;

function Wrapper({ client, children }: { client: QueryClient; children: ReactNode }) {
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

beforeEach(() => {
	openExternalMock.mockReset().mockResolvedValue(undefined);
});

describe("SessionChatSurface link routing", () => {
	it("opens a plain Chat web link in the system browser", async () => {
		const user = userEvent.setup();
		render(
			<Wrapper client={new QueryClient()}>
				<SessionChatSurface session={session} />
			</Wrapper>,
		);
		await user.click(screen.getByRole("button", { name: "Open chat link" }));

		expect(openExternalMock).toHaveBeenCalledWith(LINK);
	});

	it("does not route non-web links through the system browser", () => {
		render(
			<Wrapper client={new QueryClient()}>
				<SessionChatSurface session={session} />
			</Wrapper>,
		);
		chatLinkHandlers.onLinkOpen?.(NON_WEB_LINK);

		expect(openExternalMock).not.toHaveBeenCalled();
	});
});
