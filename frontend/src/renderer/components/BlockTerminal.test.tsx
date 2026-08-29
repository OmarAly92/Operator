import { render, screen, waitFor } from "@testing-library/react";
import { useEffect, useRef, useState } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

type RenderedBlock = { id: string; command: string; output: string; exitCode: number | null };

const mockState = vi.hoisted(() => {
	return {
		feeds: [] as Array<Uint8Array>,
		blocks: new Map<string, RenderedBlock>(),
		altScreenActive: false,
		host: undefined as { writeClipboard: (text: string) => Promise<void>; openLink: (url: string) => Promise<void> } | undefined,
		strings: undefined as Record<string, string> | undefined,
		revision: 0,
		wasmInits: 0,
	};
});

const subscribers = new Set<() => void>();
function notify(): void {
	mockState.revision += 1;
	for (const cb of subscribers) cb();
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
		}) => {
			mockState.altScreenActive = props.altScreenActive;
			if (props.host) mockState.host = props.host;
			if (props.strings) mockState.strings = props.strings;
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
		createTerminalCore: () => ({
			feed: (bytes: Uint8Array) => {
				mockState.feeds.push(bytes);
				parseFeedsForBlocks(bytes);
				notify();
			},
			snapshot: () => ({
				generation: 0,
				content: new Uint8Array(0),
				rows: new Uint32Array(0),
				runRanges: new Uint32Array(0),
				stylePairs: new Uint32Array(0),
				blocks: new Uint32Array(0),
				blockText: new Uint8Array(0),
			}),
			onChange: () => () => undefined,
			dispose: () => undefined,
		}),
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

beforeEach(() => {
	mockState.feeds = [];
	mockState.blocks = new Map();
	mockState.altScreenActive = false;
	mockState.host = undefined;
	mockState.strings = undefined;
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

	it("passes XtermTerminal as the alt-screen surface", async () => {
		const { transport, emit } = harness();
		render(
			<BlockTerminal transport={transport} sessionId="s1" historyBlocks={[]}>
				<XtermTerminalLite />
			</BlockTerminal>,
		);
		emit("\x1b[?1049h");
		await waitFor(() => expect(screen.getByTestId("xterm-surface")).toBeVisible());
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
});
