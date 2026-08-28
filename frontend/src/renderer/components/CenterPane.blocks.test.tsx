import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { ReactNode } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ConversationQueryResult } from "../hooks/useConversation";
import { blocksFromConversation } from "../lib/conversation-blocks";
import type { SessionBlocksResult } from "../hooks/useSessionBlocks";
import { installVirtualLayout } from "../test/virtual-layout";
import type { ConversationSnapshot } from "../types/conversation";
import type { WorkspaceSession } from "../types/workspace";
import { SessionBlocksPane } from "./CenterPane";
import { TooltipProvider } from "./ui/tooltip";

const sessionMocks = vi.hoisted(() => ({
	useConversation: undefined as undefined | (() => ConversationQueryResult),
	useSessionBlocks: undefined as undefined | (() => SessionBlocksResult),
	useConversationCommands: undefined as
		| undefined
		| (() => { send: (input: { text: string }) => Promise<unknown> }),
}));

vi.mock("../hooks/useSessionBlocks", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../hooks/useSessionBlocks")>();
	return {
		...actual,
		useSessionBlocks: ((sessionId: string, options: unknown) => {
			if (sessionMocks.useSessionBlocks) return sessionMocks.useSessionBlocks();
			return (actual.useSessionBlocks as (sessionId: string, options: unknown) => SessionBlocksResult)(
				sessionId,
				options,
			);
		}) as typeof actual.useSessionBlocks,
	};
});

vi.mock("../hooks/useConversation", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../hooks/useConversation")>();
	return {
		...actual,
		useConversation: ((id: string | undefined) => {
			if (sessionMocks.useConversation) return sessionMocks.useConversation();
			return (actual.useConversation as unknown as (id: string | undefined) => ConversationQueryResult)(
				id,
			);
		}) as typeof actual.useConversation,
		useConversationCommands: ((id: string | undefined) => {
			if (sessionMocks.useConversationCommands) return sessionMocks.useConversationCommands();
			return (actual.useConversationCommands as unknown as (id: string | undefined) => {
				send: (input: { text: string }) => Promise<unknown>;
			})(id);
		}) as typeof actual.useConversationCommands,
	};
});

const tuiWorker = {
	id: "sess-tui",
	workspaceId: "proj-1",
	workspaceName: "my-app",
	title: "tui worker",
	provider: "claude-code",
	kind: "worker",
	mode: "tui",
	status: "working",
	updatedAt: "2026-08-28T00:00:00Z",
	prs: [],
} satisfies WorkspaceSession;

const chatWorker = {
	id: "sess-chat",
	workspaceId: "proj-1",
	workspaceName: "my-app",
	title: "chat worker",
	provider: "codex",
	kind: "worker",
	mode: "chat",
	status: "working",
	updatedAt: "2026-08-28T00:00:00Z",
	prs: [],
} satisfies WorkspaceSession;

function chatSnapshot(): ConversationSnapshot {
	return {
		conversationId: "c-1",
		sessionId: chatWorker.id,
		harness: "codex",
		mode: "chat",
		controller: { state: "ready" },
		turns: [],
		items: [
			{
				kind: "message",
				id: "m-1",
				turnId: "t-1",
				sequence: 1,
				revision: 0,
				role: "user",
				origin: "human",
				text: "hello",
				streaming: false,
				createdAt: "2026-08-28T10:00:00Z",
			},
			{
				kind: "message",
				id: "m-2",
				turnId: "t-1",
				sequence: 2,
				revision: 0,
				role: "assistant",
				origin: "provider",
				text: "hi there",
				streaming: false,
				createdAt: "2026-08-28T10:00:01Z",
			},
		],
		latestSequence: 2,
		oldestSequence: 1,
		hasMoreBefore: false,
		settings: {},
	};
}

let teardown: () => void;

beforeEach(() => {
	sessionMocks.useConversation = undefined;
	sessionMocks.useSessionBlocks = undefined;
	sessionMocks.useConversationCommands = undefined;
	teardown = installVirtualLayout({ heights: () => [80] });
});

afterEach(() => {
	teardown();
});

function Wrapper({ children }: { children: ReactNode }) {
	return (
		<QueryClientProvider client={new QueryClient()}>
			<TooltipProvider>{children}</TooltipProvider>
		</QueryClientProvider>
	);
}

describe("SessionBlocksPane chat routing", () => {
	it("a chat session with a snapshot is supported and renders blocks from useConversation", () => {
		const snapshot = chatSnapshot();
		sessionMocks.useConversation = () => ({
			snapshot,
			isLoading: false,
			unavailable: undefined,
			error: undefined,
			hasOlder: false,
			isLoadingOlder: false,
			loadOlder: vi.fn(),
		});
		sessionMocks.useSessionBlocks = () => ({
			blocks: [],
			isLoading: false,
			isLoadingOlder: false,
			hasOlder: false,
			loadOlder: vi.fn(),
			refetch: vi.fn(),
		});

		render(
			<Wrapper>
				<SessionBlocksPane session={chatWorker} />
			</Wrapper>,
		);

		expect(screen.getByText("hello")).toBeInTheDocument();
		expect(screen.getByText("hi there")).toBeInTheDocument();
		const expectedBlocks = blocksFromConversation(snapshot);
		expect(expectedBlocks.length).toBeGreaterThan(0);
	});

	it("a chat session with unavailable is not supported and shows the unavailable reason as a non-error notice", () => {
		sessionMocks.useConversation = () => ({
			snapshot: undefined,
			isLoading: false,
			unavailable: {
				code: "SESSION_MODE_MISMATCH",
				message: "This session is a terminal session, not a chat conversation.",
			},
			error: undefined,
			hasOlder: false,
			isLoadingOlder: false,
			loadOlder: vi.fn(),
		});
		sessionMocks.useSessionBlocks = () => ({
			blocks: [],
			isLoading: false,
			isLoadingOlder: false,
			hasOlder: false,
			loadOlder: vi.fn(),
			refetch: vi.fn(),
		});

		render(
			<Wrapper>
				<SessionBlocksPane session={chatWorker} />
			</Wrapper>,
		);

		expect(
			screen.getByText(/This session is a terminal session, not a chat conversation\./),
		).toBeInTheDocument();
		expect(screen.getByText(/SESSION_MODE_MISMATCH/)).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: /retry/i })).not.toBeInTheDocument();
		expect(screen.queryByTestId("session-block")).not.toBeInTheDocument();
	});

	it("a tui session with a hook-covered harness routes through useSessionBlocks", () => {
		sessionMocks.useConversation = () => ({
			snapshot: undefined,
			isLoading: false,
			unavailable: undefined,
			error: undefined,
			hasOlder: false,
			isLoadingOlder: false,
			loadOlder: vi.fn(),
		});
		sessionMocks.useSessionBlocks = () => ({
			blocks: [],
			isLoading: false,
			isLoadingOlder: false,
			hasOlder: false,
			loadOlder: vi.fn(),
			refetch: vi.fn(),
		});

		render(
			<Wrapper>
				<SessionBlocksPane session={tuiWorker} />
			</Wrapper>,
		);

		expect(screen.getByText(/No blocks yet/i)).toBeInTheDocument();
	});

	it("renders the BlockComposer with a send function from useConversationCommands in chat mode", async () => {
		const sendMock = vi.fn().mockResolvedValue(undefined);
		sessionMocks.useConversation = () => ({
			snapshot: chatSnapshot(),
			isLoading: false,
			unavailable: undefined,
			error: undefined,
			hasOlder: false,
			isLoadingOlder: false,
			loadOlder: vi.fn(),
		});
		sessionMocks.useConversationCommands = () => ({
			send: (input: { text: string }) => {
				sendMock(input);
				return sendMock.mock.results[sendMock.mock.results.length - 1]?.value ?? Promise.resolve();
			},
		});
		sessionMocks.useSessionBlocks = () => ({
			blocks: [],
			isLoading: false,
			isLoadingOlder: false,
			hasOlder: false,
			loadOlder: vi.fn(),
			refetch: vi.fn(),
		});

		const user = userEvent.setup();
		render(
			<Wrapper>
				<SessionBlocksPane session={chatWorker} />
			</Wrapper>,
		);

		await user.type(screen.getByLabelText("Message the agent"), "ping the agent");
		await user.click(screen.getByRole("button", { name: "Send" }));

		expect(sendMock).toHaveBeenCalledWith({ text: "ping the agent" });
	});
});
