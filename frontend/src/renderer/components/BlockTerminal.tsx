import { useCallback, useEffect, useMemo, useRef, useState } from "react";
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
import { isWebLink, openLinkInSystemBrowser } from "../lib/external-link-policy";

export type BlockTerminalClipboard = {
	writeText: (text: string) => Promise<void>;
	readText?: () => Promise<string>;
};

export type BlockTerminalHistoryBlock = {
	sourceId: string;
	rawOutput: Uint8Array;
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
	clipboard?: BlockTerminalClipboard;
	ariaLabel?: string;
	fontSize?: number;
	agentTui?: boolean;
};

const DEFAULT_COLUMNS = 120;
const DEFAULT_SCROLLBACK = 5000;
const SOURCE_ID_MARKER = new TextEncoder().encode("\x1b]7000;v=1;id=");
const BEL = 0x07;

// The block terminal renders in Warp's own bundled dark theme, fixed, rather
// than following the app skin (user decision 2026-09-02). DESIGN.md's carve-out
// -- "the terminal keeps its own palette" -- is what permits this; the terminal
// therefore stays Warp-dark in light mode too, which is intended.
//
// This replaces an earlier skin bridge whose comment argued the skin must be the
// single source of colour. That still holds for the app chrome; the terminal is
// now deliberately outside it, and warpDarkTheme is its single source. Keeping
// the bridge was also what produced the white box around every block: it mapped
// blockBorder to the terminal foreground, where Warp uses the foreground at 10%.
function terminalTheme(): TerminalTheme {
	return warpDarkTheme;
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

function feedToCore(core: TerminalCore, bytes: Uint8Array, historyIds: Set<string>): void {
	const marks = scanSourceIdMarks(bytes);
	const reconnectsHistoryBlock = marks.some((mark) => historyIds.has(mark.id));
	core.feed(reconnectsHistoryBlock ? withoutRanges(bytes, marks) : bytes);
}

function feedHistory(
	core: TerminalCore,
	blocks: readonly BlockTerminalHistoryBlock[],
	historyIds: Set<string>,
): void {
	for (const block of blocks) {
		if (historyIds.has(block.sourceId)) continue;
		historyIds.add(block.sourceId);
		core.feed(block.rawOutput);
	}
}

export function BlockTerminal({
	transport,
	sessionId,
	historyBlocks,
	clipboard,
	ariaLabel,
	fontSize,
	agentTui,
}: BlockTerminalProps) {
	const { t } = useTranslation();
	const coreRef = useRef<TerminalCore | null>(null);
	const [core, setCore] = useState<TerminalCore | null>(null);
	const [altScreenActive, setAltScreenActive] = useState(false);
	const [coreError, setCoreError] = useState<Error | null>(null);
	const historyIdsRef = useRef<Set<string>>(new Set());
	const historyBlocksRef = useRef(historyBlocks);
	historyBlocksRef.current = historyBlocks;
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
				feedHistory(created, historyBlocksRef.current, historyIdsRef.current);
				const pending = pendingBytesRef.current;
				pendingBytesRef.current = [];
				terminalDebug("block-terminal", "core created", { buffered: pending.length });
				for (const bytes of pending) {
					feedToCore(created, bytes, historyIdsRef.current);
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
			historyIdsRef.current = new Set();
			setCore(null);
		};
	}, [sessionId]);

	useEffect(() => {
		coreRef.current?.setAgentTuiMode(agentTui ?? false);
	}, [agentTui]);

	useEffect(() => {
		if (!core) return;
		feedHistory(core, historyBlocks, historyIdsRef.current);
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
				feedToCore(coreRef.current, bytes, historyIdsRef.current);
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

	const resolvedTheme = useMemo<TerminalTheme>(() => terminalTheme(), []);

	// Publish the terminal's background to :root so everything behind and around
	// the grid -- the pane surface, the retained xterm slot, the overlays -- paints
	// the same colour. styles.css declares the property with a skin-owned fallback
	// for first paint; this is what makes the terminal theme the one place to
	// change it. Idempotent, so concurrent sessions cannot fight over it.
	useEffect(() => {
		document.documentElement.style.setProperty("--terminal-background", resolvedTheme.background);
	}, [resolvedTheme.background]);

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
				if (!isWebLink(url)) return;
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
			shareOutput: t("blocks.shareOutput", { defaultValue: "Save output" }),
			bookmark: t("blocks.bookmark", { defaultValue: "Bookmark" }),
			filterToCommand: t("blocks.filterToCommand", {
				defaultValue: "Filter to this command",
			}),
			jump: t("blocks.jump", { defaultValue: "Jump to block" }),
			rerunCommand: t("blocks.rerunCommand", { defaultValue: "Re-run" }),
			searchHistory: t("blocks.searchHistory", { defaultValue: "Search history" }),
			searchNoMatches: t("blocks.searchNoMatches", { defaultValue: "No matches" }),
			findPlaceholder: t("blocks.findPlaceholder", {
				defaultValue: "Find in terminal",
			}),
			findLabel: t("blocks.findLabel", { defaultValue: "Find" }),
			findMatchCount: t("blocks.findMatchCount", { defaultValue: "%1 of %2" }),
			palettePlaceholder: t("blocks.palettePlaceholder", {
				defaultValue: "Type a command",
			}),
			paletteLabel: t("blocks.paletteLabel", { defaultValue: "Command palette" }),
			paletteNoMatches: t("blocks.paletteNoMatches", {
				defaultValue: "No matching commands",
			}),
			jumpToBottom: t("blocks.jumpToBottom", { defaultValue: "Jump to bottom" }),
			shellBlocksUnavailable: t("blocks.shellBlocksUnavailable", {
				defaultValue: "Shell blocks are unavailable in this terminal.",
			}),
		}),
		[t],
	);

	const font: FontConfig = useMemo(
		() => ({
			family: '"Hack", ui-monospace, "SF Mono", Menlo, monospace',
			sizePx: fontSize ?? 14,
			lineHeight: 1.2,
			weight: 400,
			letterSpacingPx: 0,
			ligatures: false,
		}),
		[fontSize],
	);

	terminalDebug("block-terminal", "render", {
		surface: coreError ? "error" : !core ? "loading" : altScreenActive ? "block-list(alt)" : "block-list",
	});

	if (coreError || !core) {
		// Until the core exists -- and permanently if it fails to load -- the
		// pane shows an inert surface. A terminal that cannot render blocks is
		// still a terminal; replacing it with an error box, or letting the
		// failure reach the app's error boundary, turns a degraded feature into
		// a dead window.
		return (
			<div
				aria-label={ariaLabel}
				data-testid="block-terminal"
				data-alt-screen={String(altScreenActive)}
				data-block-core={coreError ? "failed" : "loading"}
				data-block-core-error={coreError ? coreError.message : undefined}
				className="block-terminal-root h-full w-full"
			/>
		);
	}

	const surfaceProps: Parameters<typeof TerminalSurface>[0] = {
		core,
		theme: resolvedTheme,
		font,
		altScreenActive: false,
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
