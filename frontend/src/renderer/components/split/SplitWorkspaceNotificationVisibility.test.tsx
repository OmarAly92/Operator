import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { NotificationDTO } from "../../lib/notifications";
import { EMPTY_LAYOUT } from "../../lib/split-layout";
import { useSplitLayoutStore } from "../../stores/split-layout-store";
import { useUiStore } from "../../stores/ui-store";
import type { WorkspaceSession, WorkspaceSummary } from "../../types/workspace";
import { NotificationRuntime } from "../NotificationCenter";
import { SplitWorkspace } from "./SplitWorkspace";

const navigateMock = vi.hoisted(() => vi.fn());

vi.mock("@tanstack/react-router", () => ({
	useNavigate: () => navigateMock,
}));

vi.mock("../../lib/shell-context", () => ({
	useShell: () => ({ daemonStatus: { state: "ready" } }),
}));

vi.mock("../../hooks/useShellTerminals", () => ({
	useShellTerminals: () => ({ data: [], isSuccess: true }),
	useCloseShellTerminal: () => ({ mutate: vi.fn() }),
	useOpenShellTerminal: () => ({ mutate: vi.fn(), isPending: false }),
	useRenameShellTerminal: () => ({ mutate: vi.fn() }),
}));

vi.mock("../../hooks/useSessionReviewer", () => ({
	useSessionReviewer: () => ({ reviewer: undefined, settled: true }),
}));

vi.mock("./SplitPane", () => ({
	SplitPane: () => <div />,
}));

vi.mock("../ui/resizable", () => ({
	ResizablePanelGroup: ({ children }: { children?: React.ReactNode }) => <div>{children}</div>,
	ResizablePanel: ({ children }: { children?: React.ReactNode }) => <div>{children}</div>,
	ResizableHandle: () => <div />,
}));

const {
	apiGetMock,
	getApiBaseUrlMock,
	onStatusMock,
	showNotificationMock,
	subscribeApiBaseUrlMock,
} = vi.hoisted(() => ({
	apiGetMock: vi.fn(),
	getApiBaseUrlMock: vi.fn(() => "http://127.0.0.1:3001"),
	onStatusMock: vi.fn(() => () => undefined),
	showNotificationMock: vi.fn(),
	subscribeApiBaseUrlMock: vi.fn(() => () => undefined),
}));

vi.mock("../../lib/api-client", () => ({
	apiClient: { GET: apiGetMock },
	apiErrorMessage: () => "Request failed",
	getApiBaseUrl: getApiBaseUrlMock,
	subscribeApiBaseUrl: subscribeApiBaseUrlMock,
}));

vi.mock("../../lib/bridge", () => ({
	operatorBridge: {
		app: {
			onCloseShellTerminalShortcut: () => () => undefined,
			setCloseShellTerminalShortcutEnabled: () => undefined,
			onPreviousTabShortcut: () => () => undefined,
			onNextTabShortcut: () => () => undefined,
		},
		daemon: { onStatus: onStatusMock },
		notifications: {
			show: showNotificationMock,
			setBadge: vi.fn(),
			onClick: () => () => undefined,
		},
	},
}));

class EventSourceStub {
	static instances: EventSourceStub[] = [];
	url: string;
	readyState = 0;
	onopen: (() => void) | null = null;
	onerror: (() => void) | null = null;
	listeners = new Map<string, (event: MessageEvent<string>) => void>();

	constructor(url: string) {
		this.url = url;
		EventSourceStub.instances.push(this);
	}

	addEventListener(type: string, listener: EventListener) {
		this.listeners.set(type, listener as (event: MessageEvent<string>) => void);
	}

	dispatch(type: string, data: unknown) {
		this.listeners.get(type)?.({ data: JSON.stringify(data) } as MessageEvent<string>);
	}

	close() {
		this.readyState = 2;
	}
}

function makeSession(id: string): WorkspaceSession {
	return {
		id,
		workspaceId: "proj-1",
		workspaceName: "proj-1",
		title: `session:${id}`,
		provider: "claude-code",
		branch: `opr/${id}`,
		status: "working",
		updatedAt: "2026-06-10T00:00:00Z",
		prs: [],
	} as unknown as WorkspaceSession;
}

const workspaces: WorkspaceSummary[] = [
	{
		id: "proj-1",
		name: "proj-1",
		path: "/p1",
		type: "main",
		sessions: [makeSession("x"), makeSession("y"), makeSession("z")],
	} as unknown as WorkspaceSummary,
];

vi.mock("../../hooks/useWorkspaceQuery", () => ({
	useWorkspaceQuery: () => ({ data: workspaces, isSuccess: true }),
}));

function s(sessionId: string): { kind: "session"; sessionId: string } {
	return { kind: "session", sessionId };
}

function notification(overrides: Partial<NotificationDTO> = {}): NotificationDTO {
	return {
		id: "ntf_1",
		sessionId: "z",
		projectId: "proj-1",
		prUrl: "",
		type: "turn_finished",
		title: "Session finished its turn",
		body: "",
		status: "unread",
		createdAt: "2026-06-16T10:00:00Z",
		target: { kind: "session", sessionId: "z" },
		quiet: false,
		...overrides,
	} as NotificationDTO;
}

describe("split-pane visibility drives who gets a toast (real layout store)", () => {
	beforeEach(() => {
		useSplitLayoutStore.setState({ layout: EMPTY_LAYOUT, dismissedReviewers: [] });
		useUiStore.setState({ visibleTerminalKindBySession: {} });
		window.localStorage.clear();
		navigateMock.mockReset();
		apiGetMock.mockReset().mockResolvedValue({ data: { notifications: [], unreadCount: 0, unresolvedCount: 0 } });
		getApiBaseUrlMock.mockReset().mockReturnValue("http://127.0.0.1:3001");
		showNotificationMock.mockReset().mockResolvedValue(undefined);
		EventSourceStub.instances = [];
		(globalThis as unknown as { EventSource: unknown }).EventSource = EventSourceStub;
		vi.spyOn(document, "visibilityState", "get").mockReturnValue("visible");
		vi.spyOn(document, "hasFocus").mockReturnValue(true);
	});

	it("marks both panes' active tabs watched and a background tab unwatched, and toasts only the unwatched session", () => {
		useSplitLayoutStore.getState().openTab(s("x"));
		const paneAId = useSplitLayoutStore.getState().layout.focusedPaneId as string;
		useSplitLayoutStore.getState().splitPane(s("y"), paneAId, "right");
		useSplitLayoutStore.getState().insertTabAfter(s("z"), s("y"));

		const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
		render(
			<QueryClientProvider client={queryClient}>
				<NotificationRuntime />
				<SplitWorkspace routeSessionId="y" />
			</QueryClientProvider>,
		);

		const kinds = useUiStore.getState().visibleTerminalKindBySession;
		expect(kinds.x).toBe("worker");
		expect(kinds.y).toBe("worker");
		expect(kinds.z).toBeUndefined();

		expect(EventSourceStub.instances).toHaveLength(1);
		const source = EventSourceStub.instances[0];
		source.dispatch("notification_created", notification({ id: "ntf_z", sessionId: "z", target: { kind: "session", sessionId: "z" } }));
		source.dispatch("notification_created", notification({ id: "ntf_x", sessionId: "x", target: { kind: "session", sessionId: "x" } }));

		expect(showNotificationMock).toHaveBeenCalledTimes(1);
		expect(showNotificationMock).toHaveBeenCalledWith(expect.objectContaining({ id: "ntf_z" }));
	});
});
