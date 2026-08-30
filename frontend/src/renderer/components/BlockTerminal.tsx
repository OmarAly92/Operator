import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import {
	TerminalSurface,
	createTerminalCore,
	initTerminalCoreFromUrl,
	warpDarkTheme,
	type FontConfig,
	type HostCapabilities,
	type TerminalCore,
	type TerminalStrings,
	type TerminalTheme,
} from "@operator/terminal-react";
import { operatorBridge } from "../lib/bridge";
import { previewBytes, terminalDebug } from "../lib/terminal-debug";
import { openLinkInSystemBrowser } from "../lib/external-link-policy";
import { useSkin } from "../theme/skin-context";
import { skinToXtermTheme } from "../theme/bridge/xterm-theme";
import type { Theme } from "../stores/ui-store";

export type BlockTerminalClipboard = {
	writeText: (text: string) => Promise<void>;
	readText?: () => Promise<string>;
};

export type BlockTerminalHistoryBlock = {
	sourceId: string;
	command: string;
	text: string;
	exitCode: number | null;
};

export type BlockTerminalTransport = {
	write: (data: Uint8Array) => void;
	onData: (listener: (bytes: Uint8Array) => void) => () => void;
	resize?: (cols: number, rows: number) => void;
	dispose?: () => void;
};

export type BlockTerminalProps = {
	transport: BlockTerminalTransport;
	sessionId: string;
	historyBlocks: BlockTerminalHistoryBlock[];
	theme?: Theme;
	clipboard?: BlockTerminalClipboard;
	ariaLabel?: string;
	fontSize?: number;
	agentTui?: boolean;
	children?: ReactNode;
};

const DEFAULT_COLUMNS = 120;
const DEFAULT_SCROLLBACK = 5000;
const SOURCE_ID_MARKER = new TextEncoder().encode("\x1b]7000;v=1;id=");
const BEL = 0x07;

// Which surface owns the alternate screen. The package's own renderer is the
// default so the pane is ours end to end; the phase-3 alternate-screen grid
// now handles full-screen TUIs end to end, so the package surface is the
// primary one. `VITE_ALT_SCREEN_SURFACE=xterm` is the spec-required escape
// hatch for any regression we cannot fix in the grid.
const handsAltScreenToXterm = import.meta.env.VITE_ALT_SCREEN_SURFACE === "xterm";

function skinToTerminalTheme(skin: ReturnType<typeof useSkin>, theme: Theme | undefined): TerminalTheme {
	if (!theme || !skin) return warpDarkTheme;
	const xterm = skinToXtermTheme(skin, theme);
	// The package's own palette is the fallback, never a literal: the skin is
	// the single source of colour, and inlining one here would be a second
	// source that drifts silently. Order is the ANSI 0-15 order the renderer
	// indexes by style code.
	const ansi = [
		xterm.black,
		xterm.red,
		xterm.green,
		xterm.yellow,
		xterm.blue,
		xterm.magenta,
		xterm.cyan,
		xterm.white,
		xterm.brightBlack,
		xterm.brightRed,
		xterm.brightGreen,
		xterm.brightYellow,
		xterm.brightBlue,
		xterm.brightMagenta,
		xterm.brightCyan,
		xterm.brightWhite,
	].map((colour, index) => colour ?? warpDarkTheme.ansi[index]) as unknown as TerminalTheme["ansi"];
	return {
		ansi,
		foreground: xterm.foreground ?? warpDarkTheme.foreground,
		background: xterm.background ?? warpDarkTheme.background,
		cursor: xterm.cursor ?? warpDarkTheme.cursor,
		selection: xterm.selectionBackground ?? warpDarkTheme.selection,
		blockBackground: xterm.background ?? warpDarkTheme.blockBackground,
		blockBorder: xterm.foreground ?? warpDarkTheme.blockBorder,
		blockHeaderForeground: xterm.foreground ?? warpDarkTheme.blockHeaderForeground,
	};
}

function encodeHistoryBlock(block: BlockTerminalHistoryBlock): Uint8Array {
	const header = `\x1b]7000;v=1;id=${block.sourceId};cmd=${encodeURIComponent(block.command)}\x07`;
	const promptStart = "\x1b]133;A\x07";
	const output = block.text.endsWith("\n") ? block.text : `${block.text}\n`;
	const exit = `\x1b]133;D;${block.exitCode ?? 0}\x07`;
	return new TextEncoder().encode(`${header}${promptStart}${output}${exit}`);
}

function isSourceIdByte(byte: number): boolean {
	return (
		(byte >= 0x30 && byte <= 0x39) ||
		(byte >= 0x41 && byte <= 0x5a) ||
		(byte >= 0x61 && byte <= 0x7a) ||
		byte === 0x5f ||
		byte === 0x2d
	);
}

function matchesAt(bytes: Uint8Array, offset: number, needle: Uint8Array): boolean {
	if (offset + needle.length > bytes.length) return false;
	for (let i = 0; i < needle.length; i += 1) {
		if (bytes[offset + i] !== needle[i]) return false;
	}
	return true;
}

type SourceIdMark = { id: string; start: number; end: number };

function scanSourceIdMarks(bytes: Uint8Array): SourceIdMark[] {
	const marks: SourceIdMark[] = [];
	for (let i = 0; i < bytes.length; i += 1) {
		if (!matchesAt(bytes, i, SOURCE_ID_MARKER)) continue;
		let cursor = i + SOURCE_ID_MARKER.length;
		const idStart = cursor;
		while (cursor < bytes.length && isSourceIdByte(bytes[cursor]!)) cursor += 1;
		if (cursor === idStart) continue;
		let terminator = cursor;
		while (terminator < bytes.length && bytes[terminator] !== BEL) terminator += 1;
		if (terminator >= bytes.length) break;
		let id = "";
		for (let at = idStart; at < cursor; at += 1) id += String.fromCharCode(bytes[at]!);
		marks.push({ id, start: i, end: terminator + 1 });
		i = terminator;
	}
	return marks;
}

function withoutRanges(bytes: Uint8Array, ranges: readonly SourceIdMark[]): Uint8Array {
	const dropped = ranges.reduce((total, range) => total + (range.end - range.start), 0);
	const out = new Uint8Array(bytes.length - dropped);
	let write = 0;
	let read = 0;
	for (const range of ranges) {
		out.set(bytes.subarray(read, range.start), write);
		write += range.start - read;
		read = range.end;
	}
	out.set(bytes.subarray(read), write);
	return out;
}

function feedToCore(
	core: TerminalCore,
	bytes: Uint8Array,
	seenLiveIds: Set<string>,
	historyIds: Set<string>,
): void {
	const marks = scanSourceIdMarks(bytes);
	let hasDuplicatedLive = false;
	for (const mark of marks) {
		seenLiveIds.add(mark.id);
		if (historyIds.has(mark.id)) hasDuplicatedLive = true;
	}
	core.feed(hasDuplicatedLive ? withoutRanges(bytes, marks) : bytes);
}

export function BlockTerminal({
	transport,
	sessionId,
	historyBlocks,
	theme,
	clipboard,
	ariaLabel,
	fontSize,
	agentTui,
	children,
}: BlockTerminalProps) {
	const { t } = useTranslation();
	const skin = useSkin();
	const coreRef = useRef<TerminalCore | null>(null);
	const [core, setCore] = useState<TerminalCore | null>(null);
	const [altScreenActive, setAltScreenActive] = useState(false);
	const [coreError, setCoreError] = useState<Error | null>(null);
	const historyIdsRef = useRef<Set<string>>(new Set());
	const seenLiveIdsRef = useRef<Set<string>>(new Set());
	// The WASM module loads asynchronously while the transport is already
	// streaming. Bytes that arrive first are held here and replayed in order
	// once the core exists, so early output is never dropped.
	const pendingBytesRef = useRef<Uint8Array[]>([]);
	const transportRef = useRef(transport);
	transportRef.current = transport;
	const agentTuiRef = useRef(agentTui ?? false);
	agentTuiRef.current = agentTui ?? false;
	const rootRef = useRef<HTMLDivElement | null>(null);
	const onSend = useCallback((text: string) => {
		transportRef.current.write(new TextEncoder().encode(`${text}\n`));
	}, []);
	const onSendRaw = useCallback((data: string) => {
		transportRef.current.write(new TextEncoder().encode(data));
	}, []);
	const onGeometry = useCallback((columns: number, rows: number) => {
		transportRef.current.resize?.(columns, rows);
	}, []);

	useEffect(() => {
		if (!core) return;
		const measure = () => {
			const root = rootRef.current;
			const host = root?.querySelector(".terminal-host") as HTMLElement | null;
			const slots = root ? [...root.querySelectorAll(".terminal-alt-slot")] : [];
			terminalDebug("block-terminal", "geometry", {
				rootH: root ? Math.round(root.getBoundingClientRect().height) : null,
				rootW: root ? Math.round(root.getBoundingClientRect().width) : null,
				hostH: host ? Math.round(host.getBoundingClientRect().height) : null,
				slots: slots.map((slot) => ({
					hidden: (slot as HTMLElement).hidden,
					h: Math.round(slot.getBoundingClientRect().height),
				})),
				rows: root ? root.querySelectorAll("[data-terminal-row]").length : 0,
				blocks: root ? root.querySelectorAll("[data-terminal-block-id]").length : 0,
			});
		};
		const first = window.setTimeout(measure, 500);
		const second = window.setTimeout(measure, 3000);
		return () => {
			window.clearTimeout(first);
			window.clearTimeout(second);
		};
	}, [core, altScreenActive]);

	useEffect(() => {
		// The WASM module has to be fetched and instantiated before a core can
		// exist: `createTerminalCore` throws "terminal core WASM is not
		// initialized" otherwise. `ensureInitialized` behind this call is
		// idempotent and shared, so every pane after the first resolves from
		// the already-instantiated module rather than refetching.
		let cancelled = false;
		let created: TerminalCore | null = null;
		void (async () => {
			try {
				await initTerminalCoreFromUrl();
				terminalDebug("block-terminal", "wasm initialized");
				if (cancelled) {
					return;
				}
				created = createTerminalCore({
					columns: DEFAULT_COLUMNS,
					scrollback: DEFAULT_SCROLLBACK,
				});
				created.setAgentTuiMode(agentTuiRef.current);
				coreRef.current = created;
				const pending = pendingBytesRef.current;
				pendingBytesRef.current = [];
				terminalDebug("block-terminal", "core created", { buffered: pending.length });
				for (const bytes of pending) {
					feedToCore(created, bytes, seenLiveIdsRef.current, historyIdsRef.current);
				}
				setCore(created);
			} catch (error) {
				terminalDebug("block-terminal", "core FAILED", { error: String(error) });
				if (!cancelled) {
					setCoreError(error instanceof Error ? error : new Error(String(error)));
				}
			}
		})();
		return () => {
			cancelled = true;
			created?.dispose();
			coreRef.current = null;
			pendingBytesRef.current = [];
			setCore(null);
		};
	}, [sessionId]);

	useEffect(() => {
		coreRef.current?.setAgentTuiMode(agentTui ?? false);
	}, [agentTui]);

	useEffect(() => {
		if (!core) return;
		for (const block of historyBlocks) {
			if (historyIdsRef.current.has(block.sourceId)) continue;
			historyIdsRef.current.add(block.sourceId);
			core.feed(encodeHistoryBlock(block));
		}
	}, [core, historyBlocks]);

	useEffect(() => {
		if (!core) return;
		const read = () => setAltScreenActive(core.snapshot().altScreen !== null);
		read();
		return core.onChange(read);
	}, [core]);

	useEffect(() => {
		terminalDebug("block-terminal", "subscribing to transport", { sessionId });
		let chunks = 0;
		let bytesSeen = 0;
		const unsubscribe = transport.onData((bytes) => {
			chunks += 1;
			bytesSeen += bytes.length;
			if (chunks <= 3 || chunks % 50 === 0) {
				terminalDebug("block-terminal", "bytes", {
					chunk: chunks,
					len: bytes.length,
					total: bytesSeen,
					hasCore: Boolean(coreRef.current),
					head: previewBytes(bytes),
				});
			}
			if (coreRef.current) {
				feedToCore(coreRef.current, bytes, seenLiveIdsRef.current, historyIdsRef.current);
			} else {
				pendingBytesRef.current.push(bytes);
			}
		});
		return () => {
			unsubscribe();
		};
	}, [transport]);

	useEffect(() => {
		return () => transport.dispose?.();
	}, [transport]);

	const resolvedTheme = useMemo<TerminalTheme>(
		() => skinToTerminalTheme(skin, theme),
		[skin, theme],
	);

	const host = useMemo<HostCapabilities>(
		() => ({
			writeClipboard: async (text: string) => {
				if (clipboard) {
					await clipboard.writeText(text);
					return;
				}
				await operatorBridge.clipboard.writeText(text);
			},
			readClipboard: async () => {
				if (clipboard?.readText) return clipboard.readText();
				return operatorBridge.clipboard.readText();
			},
			openLink: async (url: string) => {
				await openLinkInSystemBrowser(url);
			},
		}),
		[clipboard],
	);

	const strings = useMemo<TerminalStrings>(
		() => ({
			blockRunning: t("blocks.running", { defaultValue: "Running" }),
			blockSucceeded: t("blocks.succeeded", { defaultValue: "Succeeded" }),
			blockFailed: t("blocks.failed", { defaultValue: "Failed" }),
			blockAbandoned: t("blocks.abandoned", { defaultValue: "Abandoned" }),
			copyCommand: t("blocks.copyCommand", { defaultValue: "Copy command" }),
			copyOutput: t("blocks.copyOutput", { defaultValue: "Copy output" }),
			rerunCommand: t("blocks.rerunCommand", { defaultValue: "Re-run" }),
			searchHistory: t("blocks.searchHistory", { defaultValue: "Search history" }),
			searchNoMatches: t("blocks.searchNoMatches", { defaultValue: "No matches" }),
			shellBlocksUnavailable: t("blocks.shellBlocksUnavailable", {
				defaultValue: "Shell blocks are unavailable in this terminal.",
			}),
		}),
		[t],
	);

	const font: FontConfig = useMemo(
		() => ({
			family: 'ui-monospace, "SF Mono", Menlo, monospace',
			sizePx: fontSize ?? 14,
			lineHeight: 1.2,
			weight: 400,
			letterSpacingPx: 0,
			ligatures: false,
		}),
		[fontSize],
	);

	const handOffAltScreen = altScreenActive && handsAltScreenToXterm;

	terminalDebug("block-terminal", "render", {
		surface: coreError
			? "error"
			: !core
				? "loading"
				: handOffAltScreen
					? "xterm(alt)"
					: altScreenActive
						? "block-list(alt)"
						: "block-list",
	});

	if (coreError || !core) {
		// Until the core exists -- and permanently if it fails to load -- the
		// pane shows the raw surface the host handed us. A terminal that cannot
		// render blocks is still a terminal; replacing it with an error box, or
		// letting the failure reach the app's error boundary, turns a degraded
		// feature into a dead window.
		return (
			<div
				aria-label={ariaLabel}
				data-testid="block-terminal"
				data-alt-screen={String(altScreenActive)}
				data-block-core={coreError ? "failed" : "loading"}
				data-block-core-error={coreError ? coreError.message : undefined}
				className="block-terminal-root h-full w-full"
			>
				{children}
			</div>
		);
	}

	const surfaceProps: Parameters<typeof TerminalSurface>[0] = {
		core,
		theme: resolvedTheme,
		font,
		altScreenActive: handOffAltScreen,
		altScreenSurface: children,
		host,
		strings,
		onSend,
		onSendRaw,
		onGeometry,
	};

	return (
		<div
			aria-label={ariaLabel}
			data-testid="block-terminal"
			data-alt-screen={String(altScreenActive)}
			className="block-terminal-root h-full w-full"
			ref={rootRef}
		>
			<TerminalSurface {...surfaceProps} />
		</div>
	);
}
