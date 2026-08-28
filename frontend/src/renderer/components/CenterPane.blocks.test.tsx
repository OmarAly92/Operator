import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen } from "@testing-library/react";
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

type CommandsStub = ReturnType<typeof import("../hooks/useConversation").useConversationCommands>;

const sessionMocks = vi.hoisted(() => ({
	useConversation: undefined as undefined | (() => ConversationQueryResult),
	useSessionBlocks: undefined as undefined | (() => SessionBlocksResult),
	useConversationCommands: undefined as
		| undefined
		| (() => { send: (input: { text: string }) => Promise<unknown> }),
	commands: undefined as undefined | (() => Partial<CommandsStub>),
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
			if (sessionMocks.commands) return sessionMocks.commands() as CommandsStub;
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
	provider: "aider",
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
	sessionMocks.commands = undefined;
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
			refetch: vi.fn(),
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
			refetch: vi.fn(),
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
			refetch: vi.fn(),
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
			refetch: vi.fn(),
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

function approvalActivity(id: string, status: "pending" | "resolved" = "pending") {
	return {
		kind: "activity" as const,
		id,
		turnId: "t-1",
		sequence: 10,
		revision: 0,
		activityKind: "approval" as const,
		status,
		summary: "Bash",
		detail: {},
		decisions: [
			{ id: "accept", label: "Allow" },
			{ id: "reject", label: "Deny" },
		],
		requestId: id,
		createdAt: "2026-08-28T10:00:00Z",
	};
}

function userInputActivity(id: string, status: "pending" | "resolved" = "pending") {
	return {
		kind: "activity" as const,
		id,
		turnId: "t-1",
		sequence: 10,
		revision: 0,
		activityKind: "user_input" as const,
		status,
		summary: "Pick a color",
		detail: {},
		requestId: id,
		createdAt: "2026-08-28T10:00:00Z",
	};
}

function chatTurn(id: string, state: "completed" | "running" | "queued" = "completed") {
	return {
		id,
		state,
		rolledBack: false,
		providerTurnId: `provider-${id}`,
		requestedAt: "2026-08-28T10:00:00Z",
		startedAt: "2026-08-28T10:00:01Z",
		completedAt: state === "completed" ? "2026-08-28T10:00:05Z" : undefined,
	};
}

function chatSnapshotWith(options: {
	activities: ReturnType<typeof approvalActivity>[] | ReturnType<typeof userInputActivity>[];
	turns: ReturnType<typeof chatTurn>[];
	capabilities: string[];
}): ConversationSnapshot {
	return {
		conversationId: "c-1",
		sessionId: chatWorker.id,
		harness: "codex",
		mode: "chat",
		controller: { state: "ready" },
		turns: options.turns,
		items: [
			{
				kind: "message",
				id: "m-1",
				turnId: "t-1",
				sequence: 1,
				revision: 0,
				role: "user",
				origin: "human",
				text: "do the thing",
				streaming: false,
				createdAt: "2026-08-28T10:00:00Z",
			},
			...options.activities,
		],
		latestSequence: 10,
		oldestSequence: 1,
		hasMoreBefore: false,
		settings: {},
		capabilities: options.capabilities,
	};
}

describe("CenterPane capability-gated action wiring", () => {
	it("prefills the chat composer for rerun without sending the prompt", async () => {
		const send = vi.fn().mockResolvedValue(undefined);
		sessionMocks.useConversation = () => ({
			snapshot: chatSnapshot(),
			isLoading: false,
			unavailable: undefined,
			error: undefined,
			hasOlder: false,
			isLoadingOlder: false,
			loadOlder: vi.fn(),
			refetch: vi.fn(),
		});
		sessionMocks.commands = () => ({ send });

		const user = userEvent.setup();
		render(
			<Wrapper>
				<SessionBlocksPane session={chatWorker} />
			</Wrapper>,
		);

		await user.click(screen.getByTestId("block-action-rerun"));
		expect(screen.getByLabelText("Message the agent")).toHaveValue("hello");
		expect(send).not.toHaveBeenCalled();
	});

	it("renders the per-block rewind action when the daemon reports literal rollback capability", () => {
		sessionMocks.useConversation = () => ({
			snapshot: chatSnapshotWith({
				activities: [],
				turns: [chatTurn("t-1", "completed")],
				capabilities: ["rollback"],
			}),
			isLoading: false,
			unavailable: undefined,
			error: undefined,
			hasOlder: false,
			isLoadingOlder: false,
			loadOlder: vi.fn(),
			refetch: vi.fn(),
		});
		sessionMocks.commands = () => ({ rollback: vi.fn() });

		render(
			<Wrapper>
				<SessionBlocksPane session={chatWorker} />
			</Wrapper>,
		);

		expect(screen.getAllByTestId("block-action-rewind").length).toBeGreaterThan(0);
	});

	it("does not render the per-block rewind action without literal rollback capability", () => {
		sessionMocks.useConversation = () => ({
			snapshot: chatSnapshotWith({
				activities: [],
				turns: [chatTurn("t-1", "completed")],
				capabilities: ["streaming"],
			}),
			isLoading: false,
			unavailable: undefined,
			error: undefined,
			hasOlder: false,
			isLoadingOlder: false,
			loadOlder: vi.fn(),
			refetch: vi.fn(),
		});
		sessionMocks.commands = () => ({ rollback: vi.fn() });

		render(
			<Wrapper>
				<SessionBlocksPane session={chatWorker} />
			</Wrapper>,
		);

		expect(screen.queryByTestId("block-action-rewind")).not.toBeInTheDocument();
	});

	it("renders one button per provider decision when the snapshot's capabilities include 'approvals'", () => {
		const resolve = vi.fn();
		sessionMocks.useConversation = () => ({
			snapshot: chatSnapshotWith({
				activities: [approvalActivity("req-1")],
				turns: [chatTurn("t-1")],
				capabilities: ["approvals"],
			}),
			isLoading: false,
			unavailable: undefined,
			error: undefined,
			hasOlder: false,
			isLoadingOlder: false,
			loadOlder: vi.fn(),
			refetch: vi.fn(),
		});
		sessionMocks.commands = () => ({ resolve });
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

		expect(screen.getByTestId("block-decision-accept")).toBeInTheDocument();
		expect(screen.getByTestId("block-decision-reject")).toBeInTheDocument();
		expect(screen.getByText("Allow")).toBeInTheDocument();
		expect(screen.getByText("Deny")).toBeInTheDocument();
	});

	it("does not render approve or deny buttons when the snapshot's capabilities are empty", () => {
		sessionMocks.useConversation = () => ({
			snapshot: chatSnapshotWith({
				activities: [approvalActivity("req-1")],
				turns: [chatTurn("t-1")],
				capabilities: [],
			}),
			isLoading: false,
			unavailable: undefined,
			error: undefined,
			hasOlder: false,
			isLoadingOlder: false,
			loadOlder: vi.fn(),
			refetch: vi.fn(),
		});
		sessionMocks.commands = () => ({ resolve: vi.fn() });
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

		expect(screen.queryByTestId("block-decision-accept")).not.toBeInTheDocument();
		expect(screen.queryByTestId("block-decision-reject")).not.toBeInTheDocument();
	});

	it("calls the resolve mutation with the provider's own decision id, never a synthesized one", () => {
		const resolve = vi.fn();
		sessionMocks.useConversation = () => ({
			snapshot: chatSnapshotWith({
				activities: [approvalActivity("req-1")],
				turns: [chatTurn("t-1")],
				capabilities: ["approvals"],
			}),
			isLoading: false,
			unavailable: undefined,
			error: undefined,
			hasOlder: false,
			isLoadingOlder: false,
			loadOlder: vi.fn(),
			refetch: vi.fn(),
		});
		sessionMocks.commands = () => ({ resolve });
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

		fireEvent.click(screen.getByTestId("block-decision-accept"));
		expect(resolve).toHaveBeenCalledWith("req-1", "accept");
	});

	it("renders the elicitation surface when the snapshot's capabilities include 'elicitation'", () => {
		sessionMocks.useConversation = () => ({
			snapshot: chatSnapshotWith({
				activities: [userInputActivity("req-2")],
				turns: [chatTurn("t-1")],
				capabilities: ["elicitation"],
			}),
			isLoading: false,
			unavailable: undefined,
			error: undefined,
			hasOlder: false,
			isLoadingOlder: false,
			loadOlder: vi.fn(),
			refetch: vi.fn(),
		});
		sessionMocks.commands = () => ({ resolveInput: vi.fn().mockResolvedValue(undefined) });
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

		expect(screen.getByLabelText("Agent question")).toBeInTheDocument();
	});

	it("does not render the answer button when the snapshot's capabilities are empty", () => {
		sessionMocks.useConversation = () => ({
			snapshot: chatSnapshotWith({
				activities: [userInputActivity("req-2")],
				turns: [chatTurn("t-1")],
				capabilities: [],
			}),
			isLoading: false,
			unavailable: undefined,
			error: undefined,
			hasOlder: false,
			isLoadingOlder: false,
			loadOlder: vi.fn(),
			refetch: vi.fn(),
		});
		sessionMocks.commands = () => ({ resolveInput: vi.fn() });
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

		expect(screen.queryByLabelText("Agent question")).not.toBeInTheDocument();
	});

	it("renders the rollback button when the snapshot's capabilities include 'rollback' and the turn is rollback-eligible", () => {
		const rollback = vi.fn().mockResolvedValue(undefined);
		sessionMocks.useConversation = () => ({
			snapshot: chatSnapshotWith({
				activities: [],
				turns: [chatTurn("t-1", "completed")],
				capabilities: ["rollback"],
			}),
			isLoading: false,
			unavailable: undefined,
			error: undefined,
			hasOlder: false,
			isLoadingOlder: false,
			loadOlder: vi.fn(),
			refetch: vi.fn(),
		});
		sessionMocks.commands = () => ({ rollback });
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

		expect(screen.getAllByTestId("turn-rollback").length).toBeGreaterThan(0);
	});

	it("does not render the rollback button when the snapshot's capabilities are empty", () => {
		sessionMocks.useConversation = () => ({
			snapshot: chatSnapshotWith({
				activities: [],
				turns: [chatTurn("t-1", "completed")],
				capabilities: [],
			}),
			isLoading: false,
			unavailable: undefined,
			error: undefined,
			hasOlder: false,
			isLoadingOlder: false,
			loadOlder: vi.fn(),
			refetch: vi.fn(),
		});
		sessionMocks.commands = () => ({ rollback: vi.fn() });
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

		expect(screen.queryByTestId("turn-rollback")).not.toBeInTheDocument();
	});
});
