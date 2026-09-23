import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, render, screen, waitFor } from "@testing-library/react";
import { useEffect, useState } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

type RenderedBlock = { id: string; command: string; output: string; exitCode: number | null };
type MockCore = {
	feed: (bytes: Uint8Array) => void;
	enqueue: (bytes: Uint8Array) => void;
	hasBacklog: () => boolean;
	snapshot: () => { altScreen: unknown; [k: string]: unknown };
	onChange: (listener: (generation: number) => void) => () => void;
	setAgentTuiMode: (on: boolean) => void;
	replayReady: () => boolean;
	dispose: () => void;
};

const mockState = vi.hoisted(() => {
	return {
		feeds: [] as Array<Uint8Array>,
		blocks: new Map<string, RenderedBlock>(),
		altScreenActive: false,
		altScreenSurfaceProvided: false,
		altScreen: null as unknown,
		core: undefined as MockCore | undefined,
		emitGeometry: undefined as ((columns: number, rows: number) => void) | undefined,
		coreOverrides: undefined as Partial<MockCore> | undefined,
		host: undefined as
			| {
					writeClipboard: (text: string) => Promise<void>;
					openLink: (url: string) => Promise<void>;
					resolveFirstPath?: (
						candidates: readonly { path: string; allowDirectory: boolean }[],
						cwd: string,
					) => Promise<{ index: number; path: string } | null>;
					openPath?: (path: string, line?: number, column?: number) => Promise<void>;
					secretPatterns?: readonly { source: string; flags?: string }[];
					predictiveEcho?: Readonly<{ thresholdMs: number }>;
				}
			| undefined,
		onHint: undefined as ((hint: { ruleId: string; text: string; path?: string; line?: number }) => void) | undefined,
		onBlockFinished: undefined as
			| ((event: { id: string; exitCode: number | null; durationMs: number | null; visible: boolean }) => void)
			| undefined,
		font: undefined as { family?: string; lineHeight?: number } | undefined,
		strings: undefined as Record<string, string> | undefined,
		onSend: undefined as ((text: string) => void) | undefined,
		onSendRaw: undefined as ((data: string) => void) | undefined,
		revision: 0,
		wasmInits: 0,
		focusToken: undefined as number | undefined,
		visible: undefined as boolean | undefined,
		// The real surface only reports geometry once its host has a non-zero
		// client box. Off means "mounted but never laid out", which is what a
		// pane behind another tab looks like.
		reportGeometry: true,
		lastGeometry: undefined as { columns: number; rows: number } | undefined,
	};
});

const subscribers = new Set<() => void>();
const coreListeners = new Set<(generation: number) => void>();
function notify(): void {
	mockState.revision += 1;
	for (const cb of subscribers) cb();
}
function notifyCore(generation: number): void {
	for (const cb of coreListeners) cb(generation);
}

function parseFeedsForBlocks(bytes: Uint8Array): void {
	const text = new TextDecoder("utf-8", { fatal: false }).decode(bytes);
	const headerRegex = /\x1b\]7000;v=1;(?:id=([A-Za-z0-9_-]+);)?cmd=([^\x07]*)\x07/g;
	let match: RegExpExecArray | null;
	while ((match = headerRegex.exec(text)) !== null) {
		const id = match[1] ?? `synth-${mockState.blocks.size}`;
		const command = decodeURIComponent(match[2]);
		const after = text.slice(match.index + match[0].length);
		const aIdx = after.indexOf("\x1b]133;A\x07");
		const dIdx = after.indexOf("\x1b]133;D;");
		const start = aIdx === -1 ? 0 : aIdx + "\x1b]133;A\x07".length;
		const end = dIdx === -1 ? after.length : dIdx;
		const output = after.slice(start, end);
		const exitStr = dIdx === -1 ? "0" : after.slice(dIdx + "\x1b]133;D;".length, after.indexOf("\x07", dIdx));
		const exitCode = Number.parseInt(exitStr, 10);
		mockState.blocks.set(id, {
			id,
			command,
			output,
			exitCode: Number.isFinite(exitCode) ? exitCode : 0,
		});
	}
}

function MockSurface(props: {
	altScreenActive: boolean;
	altScreenSurface?: React.ReactNode;
}) {
	const [, setVersion] = useState(mockState.revision);
	useEffect(() => {
		const cb = () => setVersion(mockState.revision);
		subscribers.add(cb);
		return () => {
			subscribers.delete(cb);
		};
	}, []);
	const alt = props.altScreenActive ? props.altScreenSurface : null;
	const blocksList = Array.from(mockState.blocks.values()).map((b) => (
		<article key={b.id} data-block-id={b.id}>
			<header>
				<span data-block-command>{b.command}</span>
			</header>
			<pre data-block-output>{b.output}</pre>
			{mockState.host ? (
				<div data-block-actions>
					<button type="button" onClick={() => mockState.host!.writeClipboard(b.command)}>
						{mockState.strings?.copyCommand ?? "Copy command"}
					</button>
					<button type="button" onClick={() => mockState.host!.writeClipboard(b.output)}>
						{mockState.strings?.copyOutput ?? "Copy output"}
					</button>
					<button type="button">{mockState.strings?.rerunCommand ?? "Re-run"}</button>
				</div>
			) : null}
		</article>
	));
	const accumulatedText = mockState.feeds
		.map((b) =>
			new TextDecoder("utf-8", { fatal: false })
				.decode(b)
				.replace(/\x1b\][^\x07]*\x07/g, "")
				.replace(/\x1b\[[?]?[0-9;]*[A-Za-z]/g, ""),
		)
		.join("");
	return (
		<div data-testid="terminal-surface-mock">
			{alt}
			<div data-testid="block-list">{blocksList}</div>
			<span data-testid="accumulated-text">{accumulatedText}</span>
		</div>
	);
}

vi.mock("@operator/terminal-react", () => {
	return {
		TerminalSurface: (props: {
			core: { feed: (bytes: Uint8Array) => void };
			theme: unknown;
			font: unknown;
			altScreenActive: boolean;
			altScreenSurface?: React.ReactNode;
			host?: {
				writeClipboard: (text: string) => Promise<void>;
				openLink: (url: string) => Promise<void>;
				resolveFirstPath?: (
						candidates: readonly { path: string; allowDirectory: boolean }[],
						cwd: string,
					) => Promise<{ index: number; path: string } | null>;
				openPath?: (path: string, line?: number, column?: number) => Promise<void>;
				secretPatterns?: readonly { source: string; flags?: string }[];
				predictiveEcho?: Readonly<{ thresholdMs: number }>;
			};
			strings?: Record<string, string>;
			onSend?: (text: string) => void;
			onSendRaw?: (data: string) => void;
			onGeometry?: (columns: number, rows: number) => void;
			onHint?: (hint: { ruleId: string; text: string; path?: string; line?: number }) => void;
			onBlockFinished?: (event: {
				id: string;
				exitCode: number | null;
				durationMs: number | null;
				visible: boolean;
			}) => void;
			focusToken?: number;
			visible?: boolean;
		}) => {
			mockState.focusToken = props.focusToken;
			mockState.visible = props.visible;
			mockState.onHint = props.onHint;
			mockState.onBlockFinished = props.onBlockFinished;
			mockState.altScreenActive = props.altScreenActive;
			mockState.altScreenSurfaceProvided = props.altScreenSurface !== undefined;
			if (props.host) mockState.host = props.host;
			mockState.font = props.font as { family?: string; lineHeight?: number };
			if (props.strings) mockState.strings = props.strings;
			mockState.onSend = props.onSend;
			mockState.onSendRaw = props.onSendRaw;
			mockState.emitGeometry = props.onGeometry;
			if (mockState.reportGeometry) props.onGeometry?.(80, 24);
			return <MockSurface altScreenActive={props.altScreenActive} altScreenSurface={props.altScreenSurface} />;
		},
		warpDarkTheme: {
			ansi: new Array(16).fill("#000000"),
			foreground: "#ffffff",
			background: "#000000",
			cursor: "#00c2ff",
			selection: "rgba(0,0,0,0)",
			blockBackground: "#000000",
			blockBorder: "#616161",
			blockHeaderForeground: "#f1f1f1",
		},
		// The real component must await this before creating a core; leaving it
		// off the mock is what let a missing WASM init reach the running app.
		initTerminalCoreFromUrl: async () => {
			mockState.wasmInits += 1;
		},
		createTerminalCore: () => {
			let generation = 0;
			const core: MockCore = {
				feed: (bytes: Uint8Array) => {
					mockState.feeds.push(bytes);
					parseFeedsForBlocks(bytes);
					const text = new TextDecoder("utf-8", { fatal: false }).decode(bytes);
					if (text.includes("\x1b[?1049h")) {
						mockState.altScreen = { rows: 24, columns: 80 };
					}
					if (text.includes("\x1b[?1049l")) {
						mockState.altScreen = null;
					}
					generation += 1;
					notify();
					notifyCore(generation);
				},
				enqueue: (bytes: Uint8Array) => core.feed(bytes),
				hasBacklog: () => false,
				snapshot: () => ({
					generation,
					content: new Uint8Array(0),
					rows: new Uint32Array(0),
					runRanges: new Uint32Array(0),
					stylePairs: new Uint32Array(0),
					blocks: new Uint32Array(0),
					blockText: new Uint8Array(0),
					altScreen: mockState.altScreen,
				}),
				onChange: (listener: (generation: number) => void) => {
					coreListeners.add(listener);
					return () => {
						coreListeners.delete(listener);
					};
				},
				setAgentTuiMode: vi.fn(),
				replayReady: () => false,
				dispose: () => undefined,
				...mockState.coreOverrides,
			};
			mockState.core = core;
			return core;
		},
	};
});

vi.mock("../lib/external-link-policy", () => ({
	isWebLink: (url: string) => url.startsWith("http://") || url.startsWith("https://"),
	openLinkInSystemBrowser: vi.fn(),
}));

vi.mock("../lib/bridge", () => ({
	operatorBridge: {
		clipboard: {
			writeText: vi.fn().mockResolvedValue(undefined),
			readText: vi.fn().mockResolvedValue(""),
		},
		app: {
			resolvePath: vi.fn().mockResolvedValue(null),
			resolveFirstPath: vi.fn().mockResolvedValue(null),
			openPath: vi.fn().mockResolvedValue({ cliMissing: false }),
		},
		notifications: {
			show: vi.fn().mockResolvedValue(undefined),
		},
	},
}));

vi.mock("../theme/skin-context", () => ({
	useSkin: () => ({
		skin: null,
		setSkin: () => undefined,
	}),
}));


import { BlockTerminal, type BlockTerminalHistoryBlock } from "./BlockTerminal";
import { terminalPredictiveEchoThresholdMs } from "../lib/terminal-predictive-echo";
import { useUiStore } from "../stores/ui-store";
import { operatorBridge } from "../lib/bridge";
import { openLinkInSystemBrowser } from "../lib/external-link-policy";

const openPathMock = vi.mocked(operatorBridge.app.openPath);
const resolvePathMock = vi.mocked(operatorBridge.app.resolvePath);
const resolveFirstPathMock = vi.mocked(operatorBridge.app.resolveFirstPath);
const showNotificationMock = vi.mocked(operatorBridge.notifications.show);
const openLinkMock = vi.mocked(openLinkInSystemBrowser);

// BlockTerminal reads the daemon's redaction patterns through react-query, so
// every render of it needs a client the way the app's own tree provides one.
function renderWithQuery(ui: React.ReactElement) {
	return render(<QueryClientProvider client={new QueryClient()}>{ui}</QueryClientProvider>);
}

function harness(overrides: Partial<Parameters<typeof BlockTerminal>[0]> = {}) {
	const listeners: Array<(bytes: Uint8Array) => void> = [];
	const transport = {
		write: vi.fn(),
		onData: (cb: (bytes: Uint8Array) => void) => {
			listeners.push(cb);
			return () => {};
		},
		resize: vi.fn(),
		dispose: vi.fn(),
	};
	const emit = (text: string) => listeners.forEach((cb) => cb(new TextEncoder().encode(text)));
	return { transport, emit, overrides };
}

let activeListeners: Array<(bytes: Uint8Array) => void> = [];
function encode(text: string): Uint8Array {
	return new TextEncoder().encode(text);
}
function emit(bytes: Uint8Array): void {
	for (const cb of activeListeners) cb(bytes);
}
function historyBlock(sourceId: string, command: string, body: string, exitCode = 0): BlockTerminalHistoryBlock {
	return {
		sourceId,
		rawOutput: encode(
			`\x1b]7000;v=1;id=${sourceId};cmd=${encodeURIComponent(command)}\x07\x1b]133;C\x07${body}\n\x1b]133;D;${exitCode}\x07`,
		),
	};
}
function concatFeeds(feeds: Uint8Array[]): number[] {
	return feeds.flatMap((chunk) => [...chunk]);
}
function renderTerminal(
	options: {
		historyBlocks?: BlockTerminalHistoryBlock[];
		agentTui?: boolean;
		coreOverrides?: Partial<MockCore>;
		onReplayPainted?: () => void;
		focusToken?: number;
		visible?: boolean;
		workspacePath?: string;
	} = {},
) {
	const localListeners: Array<(bytes: Uint8Array) => void> = [];
	activeListeners = localListeners;
	mockState.coreOverrides = options.coreOverrides;
	const transport = {
		write: vi.fn(),
		onData: (cb: (bytes: Uint8Array) => void) => {
			localListeners.push(cb);
			return () => {};
		},
		resize: vi.fn(),
		dispose: vi.fn(),
	};
	render(
		<QueryClientProvider client={new QueryClient()}>
			<BlockTerminal
				transport={transport}
				sessionId="s1"
				historyBlocks={options.historyBlocks ?? []}
				agentTui={options.agentTui}
				onReplayPainted={options.onReplayPainted}
				focusToken={options.focusToken}
				visible={options.visible}
				workspacePath={options.workspacePath}
			/>
		</QueryClientProvider>,
	);
	const proxy = new Proxy({} as MockCore, {
		get(_target, prop) {
			const c = mockState.core as MockCore | undefined;
			if (!c) {
				throw new Error("core not yet created");
			}
			const value = (c as unknown as Record<string | symbol, unknown>)[prop as string];
			return typeof value === "function" ? (value as (...a: unknown[]) => unknown).bind(c) : value;
		},
	});
	return { core: proxy };
}

beforeEach(() => {
	mockState.feeds = [];
	mockState.blocks = new Map();
	mockState.altScreenActive = false;
	mockState.altScreenSurfaceProvided = false;
	mockState.altScreen = null;
	mockState.core = undefined;
	mockState.coreOverrides = undefined;
	mockState.host = undefined;
	mockState.font = undefined;
	mockState.strings = undefined;
	mockState.onSend = undefined;
	mockState.onSendRaw = undefined;
	mockState.onHint = undefined;
	mockState.onBlockFinished = undefined;
	openPathMock.mockClear();
	resolvePathMock.mockReset().mockResolvedValue(null);
	resolveFirstPathMock.mockReset().mockResolvedValue(null);
	showNotificationMock.mockClear();
	openLinkMock.mockClear();
	mockState.revision = 0;
	mockState.reportGeometry = true;
	mockState.emitGeometry = undefined;
	mockState.focusToken = undefined;
	mockState.visible = undefined;
	subscribers.clear();
});

describe("BlockTerminal", () => {
	it("gives the surface the path resolver, the editor opener, the host's patterns and the two callbacks", async () => {
		renderTerminal({ workspacePath: "/work" });
		await waitFor(() => expect(mockState.host).toBeDefined());
		expect(typeof mockState.host?.resolveFirstPath).toBe("function");
		expect(typeof mockState.host?.openPath).toBe("function");
		expect(mockState.host?.secretPatterns).toEqual([]);
		expect(typeof mockState.onHint).toBe("function");
		expect(typeof mockState.onBlockFinished).toBe("function");
	});

	it("resolves hovered path candidates against the block's cwd, falling back to the session's workspace", async () => {
		resolveFirstPathMock.mockResolvedValue({ index: 0, path: "/block/a.md" });
		renderTerminal({ workspacePath: "/work" });
		await waitFor(() => expect(mockState.host?.resolveFirstPath).toBeTypeOf("function"));
		const candidates = [{ path: "a.md", allowDirectory: false }];

		await expect(mockState.host!.resolveFirstPath!(candidates, "/block")).resolves.toEqual({ index: 0, path: "/block/a.md" });
		expect(resolveFirstPathMock).toHaveBeenLastCalledWith("/block", candidates);
		await mockState.host!.resolveFirstPath!(candidates, "");
		expect(resolveFirstPathMock).toHaveBeenLastCalledWith("/work", candidates);
		expect(resolveFirstPathMock).toHaveBeenCalledTimes(2);
	});

	it("resolves a hinted path against the workspace before opening it, and only then", async () => {
		resolvePathMock.mockResolvedValue("/work/src/a.ts");
		renderWithQuery(
			<BlockTerminal
				transport={harness().transport}
				sessionId="s1"
				historyBlocks={[]}
				workspacePath="/work"
			/>,
		);
		await waitFor(() => expect(mockState.onHint).toBeTypeOf("function"));

		mockState.onHint!({ ruleId: "file-line", text: "src/a.ts:42", path: "src/a.ts", line: 42 });
		await waitFor(() => expect(resolvePathMock).toHaveBeenCalledWith("/work", "src/a.ts"));
		await waitFor(() => expect(openPathMock).toHaveBeenCalledWith("/work/src/a.ts", 42, undefined, undefined));

		resolvePathMock.mockResolvedValue(null);
		openPathMock.mockClear();
		mockState.onHint!({ ruleId: "file-line", text: "gone.ts:1", path: "gone.ts", line: 1 });
		await waitFor(() => expect(resolvePathMock).toHaveBeenCalledWith("/work", "gone.ts"));
		expect(openPathMock).not.toHaveBeenCalled();
	});

	it("opens a clicked path at its line and column in the chosen editor", async () => {
		useUiStore.setState({ openFilesIn: "vscode" });
		renderTerminal({ workspacePath: "/work" });
		await waitFor(() => expect(mockState.host?.openPath).toBeTypeOf("function"));

		await mockState.host!.openPath!("/work/src/a.ts", 42, 7);
		expect(openPathMock).toHaveBeenLastCalledWith("/work/src/a.ts", 42, 7, "vscode");

		useUiStore.setState({ openFilesIn: "system" });
		await waitFor(() => expect(mockState.host?.openPath).toBeTypeOf("function"));
		await mockState.host!.openPath!("/work/src/b.ts");
		expect(openPathMock).toHaveBeenLastCalledWith("/work/src/b.ts", undefined, undefined, undefined);
	});

	it("opens a hinted path at the hint's line in the chosen editor", async () => {
		useUiStore.setState({ openFilesIn: "zed" });
		resolvePathMock.mockResolvedValue("/work/src/a.ts");
		renderTerminal({ workspacePath: "/work" });
		await waitFor(() => expect(mockState.onHint).toBeTypeOf("function"));

		mockState.onHint!({ ruleId: "file-line", text: "src/a.ts:42", path: "src/a.ts", line: 42 });
		await waitFor(() => expect(openPathMock).toHaveBeenCalledWith("/work/src/a.ts", 42, undefined, "zed"));
		useUiStore.setState({ openFilesIn: "system" });
	});

	it("tells the user when the editor CLI was missing and the line was not applied", async () => {
		useUiStore.setState({ openFilesIn: "cursor" });
		openPathMock.mockResolvedValueOnce({ cliMissing: true });
		renderTerminal({ workspacePath: "/work" });
		await waitFor(() => expect(mockState.host?.openPath).toBeTypeOf("function"));

		await act(async () => {
			await mockState.host!.openPath!("/work/src/a.ts", 42);
		});
		expect(await screen.findByRole("status")).toHaveTextContent(
			"Opened a.ts — Cursor CLI not found, line not applied",
		);
		useUiStore.setState({ openFilesIn: "system" });
	});

	it("shows no notice when the editor opened the file", async () => {
		useUiStore.setState({ openFilesIn: "cursor" });
		renderTerminal({ workspacePath: "/work" });
		await waitFor(() => expect(mockState.host?.openPath).toBeTypeOf("function"));

		await act(async () => {
			await mockState.host!.openPath!("/work/src/a.ts", 42);
		});
		expect(screen.queryByRole("status")).toBeNull();
		useUiStore.setState({ openFilesIn: "system" });
	});

	it("opens a hinted URL in the browser and copies anything else", async () => {
		const writeText = vi.fn().mockResolvedValue(undefined);
		renderWithQuery(
			<BlockTerminal transport={harness().transport} sessionId="s1" historyBlocks={[]} clipboard={{ writeText }} />,
		);
		await waitFor(() => expect(mockState.onHint).toBeTypeOf("function"));

		mockState.onHint!({ ruleId: "url", text: "https://example.com" });
		expect(openLinkMock).toHaveBeenCalledWith("https://example.com");
		expect(openPathMock).not.toHaveBeenCalled();

		mockState.onHint!({ ruleId: "sha", text: "deadbeef" });
		await waitFor(() => expect(writeText).toHaveBeenCalledWith("deadbeef"));
	});

	it("notifies only for a long command that finished out of sight", async () => {
		renderTerminal();
		await waitFor(() => expect(mockState.onBlockFinished).toBeTypeOf("function"));

		mockState.onBlockFinished!({ id: "0:1", exitCode: 0, durationMs: 12_000, visible: true });
		mockState.onBlockFinished!({ id: "0:2", exitCode: 0, durationMs: 900, visible: false });
		mockState.onBlockFinished!({ id: "0:3", exitCode: 0, durationMs: null, visible: false });
		expect(showNotificationMock).not.toHaveBeenCalled();

		mockState.onBlockFinished!({ id: "0:4", exitCode: 1, durationMs: 12_000, visible: false });
		expect(showNotificationMock).toHaveBeenCalledWith({
			id: "block-finished:s1:0:4",
			title: "Command failed",
			body: "after 12s",
			type: "terminal",
		});
	});

	it("leaves predictive echo off while the setting is off", async () => {
		useUiStore.setState({ terminalPredictiveEcho: false });
		renderTerminal();
		await waitFor(() => expect(mockState.host).toBeDefined());
		expect(mockState.host?.predictiveEcho).toBeUndefined();
	});

	it("hands Operator's predictive-echo threshold to the surface's host when the setting is on", async () => {
		useUiStore.setState({ terminalPredictiveEcho: true });
		renderTerminal();
		await waitFor(() => expect(mockState.host?.predictiveEcho).toEqual({ thresholdMs: terminalPredictiveEchoThresholdMs }));
		useUiStore.setState({ terminalPredictiveEcho: false });
	});

	it("hands the host's focus token to the surface", async () => {
		renderTerminal({ focusToken: 3 });
		await waitFor(() => expect(mockState.core).toBeDefined());
		await waitFor(() => expect(mockState.focusToken).toBe(3));
	});

	it("hands the host's visibility to the surface", async () => {
		renderTerminal({ visible: false });
		await waitFor(() => expect(mockState.core).toBeDefined());
		await waitFor(() => expect(mockState.visible).toBe(false));
	});

	// A core is born 120x24 and only takes the pane's real grid when the surface
	// measures a laid-out host. Feeding a replay before then parses a full-screen
	// TUI redraw into the wrong grid: everything below row 24 is clipped and the
	// later resize cannot reconstruct it, which shows as an empty pane.
	it("holds output until the surface has sized the core", async () => {
		mockState.reportGeometry = false;
		renderTerminal({ agentTui: true });
		await waitFor(() => expect(mockState.core).toBeDefined());

		emit(encode("replayed while unmeasured"));
		expect(mockState.feeds).toHaveLength(0);

		mockState.emitGeometry?.(80, 37);

		await waitFor(() => expect(mockState.feeds).toHaveLength(1));
		expect(new TextDecoder().decode(mockState.feeds[0])).toBe("replayed while unmeasured");
	});

	// Once sized, bytes must flow straight through: buffering live output behind
	// a second gate would make the agent look frozen.
	it("feeds output straight through once the core is sized", async () => {
		renderTerminal({ agentTui: true });
		await waitFor(() => expect(mockState.core).toBeDefined());

		emit(encode("live"));
		expect(mockState.feeds).toHaveLength(1);
	});

	it("queues transport bytes on the core instead of parsing them inline", async () => {
		const enqueued: Uint8Array[] = [];
		renderTerminal({
			agentTui: true,
			coreOverrides: {
				enqueue: (bytes: Uint8Array) => {
					enqueued.push(bytes);
					mockState.feeds.push(bytes);
				},
			},
		});
		await waitFor(() => expect(mockState.core).toBeDefined());
		emit(encode("hello"));
		expect(enqueued).toHaveLength(1);
		expect(new TextDecoder().decode(enqueued[0]!)).toBe("hello");
	});

	it("puts the core in agent-tui mode when the pane runs an agent", async () => {
		const setAgentTuiMode = vi.fn();
		renderTerminal({ agentTui: true, coreOverrides: { setAgentTuiMode } });
		await waitFor(() => expect(setAgentTuiMode).toHaveBeenCalledWith(true));
	});

	it("leaves a plain shell pane out of agent-tui mode", async () => {
		const setAgentTuiMode = vi.fn();
		renderTerminal({ agentTui: false, coreOverrides: { setAgentTuiMode } });
		await waitFor(() => expect(setAgentTuiMode).toHaveBeenCalledWith(false));
	});

	it("publishes the terminal background to :root so the surround tracks one colour", async () => {
		useUiStore.setState({ terminalBackground: "black" });
		// Everything behind the grid -- pane surface, retained terminal slot,
		// overlays -- reads --terminal-background. Without this the surround stayed on the
		// skin's own terminal colour and drifted from the terminal itself.
		document.documentElement.style.removeProperty("--terminal-background");
		const { transport } = harness();
		renderWithQuery(<BlockTerminal transport={transport} sessionId="s1" historyBlocks={[]} />);
		await waitFor(() =>
			expect(document.documentElement.style.getPropertyValue("--terminal-background")).toBe("#000000"),
		);
	});

	it("repaints the surround when the user picks a terminal colour", async () => {
		document.documentElement.style.removeProperty("--terminal-background");
		useUiStore.setState({ terminalBackground: "charcoal" });
		const { transport } = harness();
		renderWithQuery(<BlockTerminal transport={transport} sessionId="s1" historyBlocks={[]} />);
		await waitFor(() =>
			expect(document.documentElement.style.getPropertyValue("--terminal-background")).toBe("#1d2022"),
		);
		useUiStore.setState({ terminalBackground: "black" });
	});

	it("uses Warp's line-height ratio", async () => {
		const { transport } = harness();
		renderWithQuery(<BlockTerminal transport={transport} sessionId="s1" historyBlocks={[]} />);
		await waitFor(() => expect(mockState.font).toBeDefined());
		expect(mockState.font?.lineHeight).toBe(1.2);
	});

	it("prefers the bundled Hack family", async () => {
		const { transport } = harness();
		renderWithQuery(<BlockTerminal transport={transport} sessionId="s1" historyBlocks={[]} />);
		await waitFor(() => expect(mockState.font).toBeDefined());
		expect(mockState.font?.family?.split(",")[0]).toBe('"Hack"');
	});

	it("feeds bytes from the mux channel into the core", async () => {
		const { transport, emit } = harness();
		renderWithQuery(<BlockTerminal transport={transport} sessionId="s1" historyBlocks={[]} />);
		emit("\x1b]133;A\x07\x1b]133;C\x07hello\n\x1b]133;D;0\x07");
		await waitFor(() => expect(screen.getByText(/hello/)).toBeInTheDocument());
	});

	it("writes submitted text plus one newline and passes raw bytes unchanged", async () => {
		const { transport } = harness();
		renderWithQuery(<BlockTerminal transport={transport} sessionId="s1" historyBlocks={[]} />);
		await waitFor(() => expect(mockState.onSend).toBeTypeOf("function"));
		mockState.onSend!("make test");
		mockState.onSendRaw!("\x03");
		expect(transport.write).toHaveBeenNthCalledWith(1, new TextEncoder().encode("make test\n"));
		expect(transport.write).toHaveBeenNthCalledWith(2, new TextEncoder().encode("\x03"));
	});

	it("keeps the package renderer on the alternate screen", async () => {
		const { transport, emit } = harness();
		renderWithQuery(<BlockTerminal transport={transport} sessionId="s1" historyBlocks={[]} />);
		emit("\x1b[?1049h");
		await waitFor(() => expect(mockState.altScreenActive).toBe(false));
	});

	it("routes copy actions through Operator's clipboard bridge", async () => {
		const writeText = vi.fn().mockResolvedValue(undefined);
		const { transport, emit } = harness();
		renderWithQuery(
			<BlockTerminal transport={transport} sessionId="s1" historyBlocks={[]} clipboard={{ writeText }} />,
		);
		emit("\x1b]133;A\x07\x1b]7000;v=1;cmd=ls\x07\x1b]133;C\x07a.txt\n\x1b]133;D;0\x07");
		const button = await screen.findByRole("button", { name: /copy command/i });
		button.click();
		await waitFor(() => expect(writeText).toHaveBeenCalledWith("ls"));
	});

	it("renders history blocks before any live block arrives", async () => {
		const { transport } = harness();
		renderWithQuery(
			<BlockTerminal
				transport={transport}
				sessionId="s1"
				historyBlocks={[historyBlock("block-1", "git log", "commit abc")]}
			/>,
		);
		expect(await screen.findByText(/git log/)).toBeInTheDocument();
	});

	it("feeds the exact history bytes in chronological order, then the live block", async () => {
		const h1 = historyBlock("h1", "one", "out-1").rawOutput;
		const h2 = encode("\x1b]7000;v=1;id=h2;cmd=two\x07\x1b]133;C\x07\x1b[31mout-2\x1b[0m\n\x1b]133;D;0\x07");
		const h3 = Uint8Array.from([
			0x1b, 0x5d, 0x37, 0x30, 0x30, 0x30, 0x3b, 0x76, 0x3d, 0x31, 0x3b, 0x69, 0x64, 0x3d, 0x68, 0x33,
			0x3b, 0x63, 0x6d, 0x64, 0x3d, 0x74, 0x68, 0x72, 0x65, 0x65, 0x07, 0x00, 0x01, 0x80, 0xfe, 0xff,
			0x1b, 0x5b, 0x33, 0x32, 0x6d, 0x0a,
		]);
		renderTerminal({
			historyBlocks: [
				{ sourceId: "h1", rawOutput: h1 },
				{ sourceId: "h2", rawOutput: h2 },
				{ sourceId: "h3", rawOutput: h3 },
			],
		});

		const earlyLive = encode("\x1b]7000;v=1;id=live-a;cmd=four\x07\x1b]133;C\x07out-4\n\x1b]133;D;0\x07");
		emit(earlyLive);

		await waitFor(() => expect(mockState.feeds.length).toBeGreaterThanOrEqual(4));
		expect(concatFeeds(mockState.feeds.slice(0, 4))).toEqual([...h1, ...h2, ...h3, ...earlyLive]);

		const laterLive = encode("\x1b]7000;v=1;id=live-b;cmd=five\x07\x1b]133;C\x07out-5\n\x1b]133;D;0\x07");
		emit(laterLive);
		await waitFor(() => expect(mockState.feeds.length).toBeGreaterThanOrEqual(5));
		expect(Array.from(mockState.feeds[4])).toEqual([...laterLive]);
	});

	it("upserts a live block whose id was already replayed from history, via the mock core's id-keyed seam", async () => {
		const { transport, emit } = harness();
		renderWithQuery(
			<BlockTerminal
				transport={transport}
				sessionId="s1"
				historyBlocks={[historyBlock("block-1", "git log", "commit abc")]}
			/>,
		);
		emit("\x1b]133;A\x07\x1b]7000;v=1;id=block-1;cmd=git%20log\x07\x1b]133;C\x07commit abc\n\x1b]133;D;0\x07");
		await waitFor(() => expect(screen.getAllByText(/git log/)).toHaveLength(1));
	});

	it("tells the transport its size so the pty matches the pane", async () => {
		const resize = vi.fn();
		const { transport } = harness();
		const merged = { ...transport, resize };
		renderWithQuery(<BlockTerminal transport={merged} sessionId="s1" historyBlocks={[]} />);
		await waitFor(() => expect(resize).toHaveBeenCalled());
		const [cols, rows] = resize.mock.calls.at(-1)!;
		expect(cols).toBeGreaterThan(0);
		expect(rows).toBeGreaterThan(0);
	});

	it("does not corrupt a multi-byte character split across two chunks", async () => {
		renderTerminal();
		const bar = new TextEncoder().encode("\u2500");
		expect(bar.length).toBe(3);
		emit(bar.subarray(0, 2));
		emit(bar.subarray(2));
		await waitFor(() => expect(mockState.feeds.length).toBeGreaterThanOrEqual(2));
		const seen = mockState.feeds.flatMap((chunk) => [...chunk]);
		// U+FFFD encodes as ef bf bd. Decoding each chunk with a non-streaming
		// TextDecoder and re-encoding turns one split glyph into two of these,
		// which is the box-question mark that shows up mid-separator.
		expect(seen).not.toContain(0xef);
		expect(seen.join(",")).toContain([...bar].join(","));
	});

	it("upserts a reconnecting in-flight block whose sourceId was already in history", async () => {
		const duplicate = "\u001b]7000;v=1;id=dup;cmd=ls\u0007body";
		renderTerminal({
			historyBlocks: [historyBlock("dup", "ls", "body")],
		});
		await waitFor(() => {
			const seeded = new TextDecoder().decode(
				Uint8Array.from(mockState.feeds.flatMap((chunk) => [...chunk])),
			);
			expect(seeded).toContain("id=dup");
		});
		mockState.feeds.length = 0;
		emit(encode(duplicate));
		await waitFor(() => expect(mockState.feeds.length).toBeGreaterThan(0));
		const text = new TextDecoder().decode(
			Uint8Array.from(mockState.feeds.flatMap((chunk) => [...chunk])),
		);
		expect(text).not.toContain("id=dup");
		expect(text).toContain("body");
	});

	it("takes the alternate-screen signal from the core, not from sniffing bytes", async () => {
		const { core } = renderTerminal();
		emit(encode("\x1b[?1049h"));
		await waitFor(() => {
			expect(core.snapshot().altScreen).not.toBeNull();
			expect(screen.getByTestId("block-terminal")).toHaveAttribute("data-alt-screen", "true");
		});
	});

	it("keeps the alternate screen in the package surface by default", async () => {
		renderTerminal();
		emit(encode("\x1b[?1049h"));
		await waitFor(() =>
			expect(screen.getByTestId("block-terminal")).toHaveAttribute("data-alt-screen", "true"),
		);
		expect(mockState.altScreenActive).toBe(false);
	});

	it("opens web links from the surface in the system browser", async () => {
		const { openLinkInSystemBrowser } = await import("../lib/external-link-policy");
		vi.mocked(openLinkInSystemBrowser).mockClear();
		renderTerminal();
		await waitFor(() => expect(mockState.host).toBeDefined());
		await mockState.host?.openLink("http://localhost:3000/simple");
		expect(openLinkInSystemBrowser).toHaveBeenCalledWith("http://localhost:3000/simple");
		await mockState.host?.openLink("https://example.com/pull/42");
		expect(openLinkInSystemBrowser).toHaveBeenCalledWith("https://example.com/pull/42");
	});

	it("does not open a non-web (mailto:) link externally", async () => {
		const { openLinkInSystemBrowser } = await import("../lib/external-link-policy");
		vi.mocked(openLinkInSystemBrowser).mockClear();
		renderTerminal();
		await waitFor(() => expect(mockState.host).toBeDefined());
		await mockState.host?.openLink("mailto:dev@example.com");
		expect(openLinkInSystemBrowser).not.toHaveBeenCalled();
	});

});

describe("BlockTerminal replay paint", () => {
	// The pane's cover exists to hide a progressive repaint. The block surface
	// has none: it holds bytes until the grid is sized, then feeds them as one
	// batch. Reporting that batch is what lets the cover lift on proof the
	// replay is on screen rather than on a timer.
	it("reports the replay painted once the sized grid has taken it", async () => {
		const onReplayPainted = vi.fn();
		mockState.reportGeometry = false;
		renderTerminal({ agentTui: true, onReplayPainted });
		await waitFor(() => expect(mockState.core).toBeDefined());

		emit(encode("replayed while unmeasured"));
		expect(onReplayPainted).not.toHaveBeenCalled();

		mockState.emitGeometry?.(80, 37);
		await waitFor(() => expect(mockState.feeds).toHaveLength(1));
		await waitFor(() => expect(onReplayPainted).toHaveBeenCalledTimes(1));
	});

	// Nothing was held, so nothing is proven on screen. Uncovering here would
	// race a replay still in flight and expose exactly the progressive paint the
	// cover is for; the attachment's first-byte grace owns this case instead.
	it("stays silent for a pane that had no held replay", async () => {
		const onReplayPainted = vi.fn();
		renderTerminal({ onReplayPainted });
		await waitFor(() => expect(mockState.core).toBeDefined());
		await Promise.resolve();
		expect(onReplayPainted).not.toHaveBeenCalled();
	});

	it("reports once, not again on later live output", async () => {
		const onReplayPainted = vi.fn();
		mockState.reportGeometry = false;
		renderTerminal({ onReplayPainted });
		await waitFor(() => expect(mockState.core).toBeDefined());
		emit(encode("held replay"));
		mockState.emitGeometry?.(80, 37);
		await waitFor(() => expect(onReplayPainted).toHaveBeenCalledTimes(1));

		emit(encode("live output"));
		await waitFor(() => expect(mockState.feeds.length).toBeGreaterThan(1));
		expect(onReplayPainted).toHaveBeenCalledTimes(1);
	});
});
