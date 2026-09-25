import { act, render } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { MuxConnectionState, ProgramNotification, TerminalMux } from "../lib/terminal-mux";
import type { WorkspaceSession, WorkspaceSummary } from "../types/workspace";

const { navigateMock, showMock, clickListeners } = vi.hoisted(() => ({
	navigateMock: vi.fn(),
	showMock: vi.fn(),
	clickListeners: new Set<(id: string) => void>(),
}));

vi.mock("@tanstack/react-router", () => ({ useNavigate: () => navigateMock }));

vi.mock("../lib/bridge", () => ({
	operatorBridge: {
		notifications: {
			show: showMock,
			onClick: (listener: (id: string) => void) => {
				clickListeners.add(listener);
				return () => clickListeners.delete(listener);
			},
		},
	},
}));

const session: WorkspaceSession = {
	id: "sess-1",
	terminalHandleId: "handle-1",
	workspaceId: "proj-1",
	workspaceName: "demo",
	title: "fix the tests",
	provider: "claude-code",
	branch: "main",
	status: "working",
	updatedAt: "now",
	prs: [],
};
const workspaces: WorkspaceSummary[] = [{ id: "proj-1", name: "demo", path: "/p", sessions: [session] }];

vi.mock("../hooks/useWorkspaceQuery", () => ({ useWorkspaceQuery: () => ({ data: workspaces }) }));
vi.mock("../hooks/useShellTerminals", () => ({
	useShellTerminals: () => ({
		data: [{ handleId: "shell-1", workingDir: "/p", title: "zsh", createdAt: "now" }],
	}),
}));

import { claimOnScreenTerminals } from "../lib/on-screen-terminals";
import { clearTerminalTitles, terminalTitle } from "../lib/terminal-titles";
import { ProgramRuntime, programTargets } from "./ProgramRuntime";

type Fake = {
	mux: TerminalMux;
	disposed: boolean;
	titles: Set<(handleId: string, title: string) => void>;
	notes: Set<(handleId: string, note: ProgramNotification) => void>;
	connection: Set<(state: MuxConnectionState) => void>;
};

function fakeMux(): Fake {
	const fake: Fake = { disposed: false, titles: new Set(), notes: new Set(), connection: new Set(), mux: {} as TerminalMux };
	fake.mux = {
		open: () => undefined,
		sendInput: () => undefined,
		resize: () => undefined,
		close: () => undefined,
		ack: () => undefined,
		requestOlder: () => undefined,
		onData: () => () => undefined,
		onExit: () => () => undefined,
		onOpened: () => () => undefined,
		onError: () => () => undefined,
		onHealth: () => () => undefined,
		subscribeBlocks: () => undefined,
		unsubscribeBlocks: () => undefined,
		onBlock: () => () => undefined,
		onTerminalBlock: () => () => undefined,
		onProgramTitle: (listener) => {
			fake.titles.add(listener);
			return () => fake.titles.delete(listener);
		},
		onProgramNotification: (listener) => {
			fake.notes.add(listener);
			return () => fake.notes.delete(listener);
		},
		onConnectionChange: (listener) => {
			fake.connection.add(listener);
			return () => fake.connection.delete(listener);
		},
		dispose: () => {
			fake.disposed = true;
		},
	};
	return fake;
}

function mount() {
	const fakes: Fake[] = [];
	const createMux = () => {
		const fake = fakeMux();
		fakes.push(fake);
		return fake.mux;
	};
	const view = render(<ProgramRuntime createMux={createMux} />);
	return { fakes, ...view };
}

beforeEach(() => {
	showMock.mockReset().mockResolvedValue(undefined);
	navigateMock.mockReset();
	vi.spyOn(document, "visibilityState", "get").mockReturnValue("visible");
	vi.spyOn(document, "hasFocus").mockReturnValue(true);
});

afterEach(() => {
	clearTerminalTitles();
	vi.restoreAllMocks();
});

describe("programTargets", () => {
	it("labels a session terminal with its session and a shell with its tab title", () => {
		const targets = programTargets(workspaces, [{ handleId: "shell-1", sessionId: "sess-1", projectId: "proj-1", workingDir: "/p", title: "zsh", createdAt: "now" }]);
		expect(targets.get("handle-1")).toEqual({ label: "fix the tests", sessionId: "sess-1", projectId: "proj-1" });
		expect(targets.get("shell-1")).toEqual({ label: "zsh", sessionId: "sess-1", projectId: "proj-1" });
	});
});

describe("ProgramRuntime", () => {
	it("keeps the title store in step with the daemon's program feed", () => {
		const { fakes } = mount();
		act(() => fakes[0].titles.forEach((listener) => listener("handle-1", "Number list 1 to 3000")));
		expect(terminalTitle("handle-1")).toBe("Number list 1 to 3000");
		act(() => fakes[0].titles.forEach((listener) => listener("handle-1", "")));
		expect(terminalTitle("handle-1")).toBe("");
	});

	it("toasts a program notification for a terminal that is not on screen, titled by its session", () => {
		const { fakes } = mount();
		act(() => fakes[0].notes.forEach((listener) => listener("handle-1", { title: "", body: "hello" })));
		expect(showMock).toHaveBeenCalledWith({ id: "program:handle-1:1", title: "fix the tests", body: "hello", type: "program" });
	});

	it("ignores a program notification while its terminal is on screen in a focused window", () => {
		const release = claimOnScreenTerminals(["handle-1"]);
		const { fakes } = mount();
		act(() => fakes[0].notes.forEach((listener) => listener("handle-1", { title: "", body: "hello" })));
		expect(showMock).not.toHaveBeenCalled();
		vi.spyOn(document, "hasFocus").mockReturnValue(false);
		act(() => fakes[0].notes.forEach((listener) => listener("handle-1", { title: "", body: "again" })));
		expect(showMock).toHaveBeenCalledTimes(1);
		release();
	});

	it("falls back to a generic title for a terminal it cannot name", () => {
		const { fakes } = mount();
		act(() => fakes[0].notes.forEach((listener) => listener("unknown", { title: "", body: "hi" })));
		expect(showMock).toHaveBeenCalledWith(expect.objectContaining({ title: "Terminal", body: "hi" }));
	});

	it("opens the session when its program toast is clicked", () => {
		mount();
		act(() => clickListeners.forEach((listener) => listener("program:handle-1:4")));
		expect(navigateMock).toHaveBeenCalledWith({
			to: "/projects/$projectId/sessions/$sessionId",
			params: { projectId: "proj-1", sessionId: "sess-1" },
		});
		act(() => clickListeners.forEach((listener) => listener("ntf_other")));
		expect(navigateMock).toHaveBeenCalledTimes(1);
	});

	it("closes the feed and removes its click listener when unmounted", () => {
		const { fakes, unmount } = mount();
		const clicksBefore = clickListeners.size;
		unmount();
		expect(fakes[0].disposed).toBe(true);
		expect(fakes[0].titles.size).toBe(0);
		expect(fakes[0].notes.size).toBe(0);
		expect(clickListeners.size).toBe(clicksBefore - 1);
	});
});
