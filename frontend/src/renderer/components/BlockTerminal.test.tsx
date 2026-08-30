import { render, screen, waitFor } from "@testing-library/react";
import { useEffect, useRef, useState } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

type RenderedBlock = { id: string; command: string; output: string; exitCode: number | null };
type MockCore = {
	feed: (bytes: Uint8Array) => void;
	snapshot: () => { altScreen: unknown; [k: string]: unknown };
	onChange: (listener: (generation: number) => void) => () => void;
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
		host: undefined as { writeClipboard: (text: string) => Promise<void>; openLink: (url: string) => Promise<void> } | undefined,
		strings: undefined as Record<string, string> | undefined,
		onSend: undefined as ((text: string) => void) | undefined,
		onSendRaw: undefined as ((data: string) => void) | undefined,
		revision: 0,
		wasmInits: 0,
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
			host?: { writeClipboard: (text: string) => Promise<void>; openLink: (url: string) => Promise<void> };
			strings?: Record<string, string>;
			onSend?: (text: string) => void;
			onSendRaw?: (data: string) => void;
			onGeometry?: (columns: number, rows: number) => void;
		}) => {
			mockState.altScreenActive = props.altScreenActive;
			mockState.altScreenSurfaceProvided = props.altScreenSurface !== undefined;
			if (props.host) mockState.host = props.host;
			if (props.strings) mockState.strings = props.strings;
			mockState.onSend = props.onSend;
			mockState.onSendRaw = props.onSendRaw;
			props.onGeometry?.(80, 24);
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
				dispose: () => undefined,
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
	},
}));

vi.mock("../theme/skin-context", () => ({
	useSkin: () => ({
		skin: null,
		setSkin: () => undefined,
	}),
}));

vi.mock("../theme/bridge/xterm-theme", () => ({
	skinToXtermTheme: () => ({
		black: "#000",
		red: "#f00",
		green: "#0f0",
		yellow: "#ff0",
		blue: "#00f",
		magenta: "#f0f",
		cyan: "#0ff",
		white: "#fff",
		brightBlack: "#888",
		brightRed: "#f88",
		brightGreen: "#8f8",
		brightYellow: "#ff8",
		brightBlue: "#88f",
		brightMagenta: "#f8f",
		brightCyan: "#8ff",
		brightWhite: "#fff",
		foreground: "#fff",
		background: "#000",
		cursor: "#0ff",
		selectionBackground: "rgba(0,0,0,0)",
	}),
}));

vi.mock("./XtermTerminal", () => ({
	XtermTerminal: () => {
		const ref = useRef<HTMLDivElement | null>(null);
		useEffect(() => {
			if (ref.current) ref.current.setAttribute("data-mounted", "true");
		}, []);
		return <div ref={ref} data-testid="xterm-surface" />;
	},
}));

import { BlockTerminal } from "./BlockTerminal";

function XtermTerminalLite() {
	return <div data-testid="xterm-surface" />;
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
function renderTerminal() {
	const localListeners: Array<(bytes: Uint8Array) => void> = [];
	activeListeners = localListeners;
	const transport = {
		write: vi.fn(),
		onData: (cb: (bytes: Uint8Array) => void) => {
			localListeners.push(cb);
			return () => {};
		},
		resize: vi.fn(),
		dispose: vi.fn(),
	};
	render(<BlockTerminal transport={transport} sessionId="s1" historyBlocks={[]} />);
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
	mockState.host = undefined;
	mockState.strings = undefined;
	mockState.onSend = undefined;
	mockState.onSendRaw = undefined;
	mockState.revision = 0;
	subscribers.clear();
});

describe("BlockTerminal", () => {
	it("feeds bytes from the mux channel into the core", async () => {
		const { transport, emit } = harness();
		render(<BlockTerminal transport={transport} sessionId="s1" historyBlocks={[]} />);
		emit("\x1b]133;A\x07\x1b]133;C\x07hello\n\x1b]133;D;0\x07");
		await waitFor(() => expect(screen.getByText(/hello/)).toBeInTheDocument());
	});

	it("writes submitted text plus one newline and passes raw bytes unchanged", async () => {
		const { transport } = harness();
		render(<BlockTerminal transport={transport} sessionId="s1" historyBlocks={[]} />);
		await waitFor(() => expect(mockState.onSend).toBeTypeOf("function"));
		mockState.onSend!("make test");
		mockState.onSendRaw!("\x03");
		expect(transport.write).toHaveBeenNthCalledWith(1, new TextEncoder().encode("make test\n"));
		expect(transport.write).toHaveBeenNthCalledWith(2, new TextEncoder().encode("\x03"));
	});

	it("keeps the package renderer on the alternate screen by default", async () => {
		const { transport, emit } = harness();
		render(
			<BlockTerminal transport={transport} sessionId="s1" historyBlocks={[]}>
				<XtermTerminalLite />
			</BlockTerminal>,
		);
		emit("\x1b[?1049h");
		// The default is the package's own surface even in the alternate screen;
		// handing it to xterm is opt-in via VITE_ALT_SCREEN_SURFACE=xterm.
		await waitFor(() => expect(mockState.altScreenActive).toBe(false));
	});

	it("still hands XtermTerminal to the surface so the opt-in path has something to show", async () => {
		const { transport, emit } = harness();
		render(
			<BlockTerminal transport={transport} sessionId="s1" historyBlocks={[]}>
				<XtermTerminalLite />
			</BlockTerminal>,
		);
		emit("\x1b[?1049h");
		// This asserted visibility before the package renderer became the default
		// alt-screen surface, at which point it started passing only because the
		// loading branch also renders children. What matters now is that the
		// surface still receives it, so VITE_ALT_SCREEN_SURFACE=xterm has a
		// surface to hand the alternate screen back to.
		await waitFor(() => expect(mockState.altScreenSurfaceProvided).toBe(true));
	});

	it("routes copy actions through Operator's clipboard bridge", async () => {
		const writeText = vi.fn().mockResolvedValue(undefined);
		const { transport, emit } = harness();
		render(
			<BlockTerminal transport={transport} sessionId="s1" historyBlocks={[]} clipboard={{ writeText }} />,
		);
		emit("\x1b]133;A\x07\x1b]7000;v=1;cmd=ls\x07\x1b]133;C\x07a.txt\n\x1b]133;D;0\x07");
		const button = await screen.findByRole("button", { name: /copy command/i });
		button.click();
		await waitFor(() => expect(writeText).toHaveBeenCalledWith("ls"));
	});

	it("renders history blocks before any live block arrives", async () => {
		const { transport } = harness();
		render(
			<BlockTerminal
				transport={transport}
				sessionId="s1"
				historyBlocks={[{ sourceId: "block-1", command: "git log", text: "commit abc", exitCode: 0 }]}
			/>,
		);
		expect(await screen.findByText(/git log/)).toBeInTheDocument();
	});

	it("does not duplicate a block present in both history and the live stream", async () => {
		const { transport, emit } = harness();
		render(
			<BlockTerminal
				transport={transport}
				sessionId="s1"
				historyBlocks={[{ sourceId: "block-1", command: "git log", text: "commit abc", exitCode: 0 }]}
			/>,
		);
		emit("\x1b]133;A\x07\x1b]7000;v=1;id=block-1;cmd=git%20log\x07\x1b]133;C\x07commit abc\n\x1b]133;D;0\x07");
		await waitFor(() => expect(screen.getAllByText(/git log/)).toHaveLength(1));
	});

	it("tells the transport its size so the pty matches the pane", async () => {
		const resize = vi.fn();
		const { transport } = harness();
		const merged = { ...transport, resize };
		render(<BlockTerminal transport={merged} sessionId="s1" historyBlocks={[]} />);
		await waitFor(() => expect(resize).toHaveBeenCalled());
		const [cols, rows] = resize.mock.calls.at(-1)!;
		expect(cols).toBeGreaterThan(0);
		expect(rows).toBeGreaterThan(0);
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

	it("still hands the alternate screen to xterm when the flag says so", async () => {
		vi.stubEnv("VITE_ALT_SCREEN_SURFACE", "xterm");
		vi.resetModules();
		try {
			const reloaded = await import("./BlockTerminal");
			const localListeners: Array<(bytes: Uint8Array) => void> = [];
			activeListeners = localListeners;
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
				<reloaded.BlockTerminal transport={transport} sessionId="s-xterm" historyBlocks={[]}>
					<div data-testid="xterm-fallback" />
				</reloaded.BlockTerminal>,
			);
			emit(encode("\x1b[?1049h"));
			await waitFor(() => expect(mockState.altScreenActive).toBe(true));
			expect(mockState.altScreenSurfaceProvided).toBe(true);
		} finally {
			vi.unstubAllEnvs();
			vi.resetModules();
		}
	});
});
