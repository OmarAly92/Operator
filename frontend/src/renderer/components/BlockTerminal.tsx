import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
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
	children?: ReactNode;
};

const DEFAULT_COLUMNS = 120;
const DEFAULT_SCROLLBACK = 5000;
const ALT_SCREEN_ENTER = "\x1b[?1049h";
const ALT_SCREEN_LEAVE = "\x1b[?1049l";
const SOURCE_ID_PATTERN = /\x1b\]7000;v=1;id=([A-Za-z0-9_-]+)/g;

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

function feedToCore(
	core: TerminalCore,
	bytes: Uint8Array,
	seenLiveIds: Set<string>,
	historyIds: Set<string>,
): void {
	const text = new TextDecoder("utf-8", { fatal: false }).decode(bytes);
	SOURCE_ID_PATTERN.lastIndex = 0;
	let match: RegExpExecArray | null;
	let filtered = text;
	let hasDuplicatedLive = false;
	while ((match = SOURCE_ID_PATTERN.exec(text)) !== null) {
		const id = match[1];
		seenLiveIds.add(id);
		if (historyIds.has(id)) {
			hasDuplicatedLive = true;
		}
	}
	if (hasDuplicatedLive) {
		filtered = text.replace(/\x1b\]7000;v=1;id=[A-Za-z0-9_-]+;?[^\x07]*\x07/g, "");
	}
	core.feed(new TextEncoder().encode(filtered));
}

export function BlockTerminal({
	transport,
	sessionId,
	historyBlocks,
	theme,
	clipboard,
	ariaLabel,
	fontSize,
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
				if (cancelled) {
					return;
				}
				created = createTerminalCore({
					columns: DEFAULT_COLUMNS,
					scrollback: DEFAULT_SCROLLBACK,
				});
				coreRef.current = created;
				const pending = pendingBytesRef.current;
				pendingBytesRef.current = [];
				for (const bytes of pending) {
					feedToCore(created, bytes, seenLiveIdsRef.current, historyIdsRef.current);
				}
				setCore(created);
			} catch (error) {
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
		if (!core) return;
		for (const block of historyBlocks) {
			if (historyIdsRef.current.has(block.sourceId)) continue;
			historyIdsRef.current.add(block.sourceId);
			core.feed(encodeHistoryBlock(block));
		}
	}, [core, historyBlocks]);

	useEffect(() => {
		const unsubscribe = transport.onData((bytes) => {
			const text = new TextDecoder("utf-8", { fatal: false }).decode(bytes);
			if (text.includes(ALT_SCREEN_ENTER)) setAltScreenActive(true);
			if (text.includes(ALT_SCREEN_LEAVE)) setAltScreenActive(false);
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
			lineHeight: 1.35,
			weight: 400,
			letterSpacingPx: 0,
			ligatures: false,
		}),
		[fontSize],
	);

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
				data-block-core={coreError ? "failed" : "loading"}
				data-block-core-error={coreError ? coreError.message : undefined}
				className="block-terminal-root h-full w-full"
			>
				{children}
			</div>
		);
	}

	const surfaceProps = {
		core,
		theme: resolvedTheme,
		font,
		altScreenActive,
		altScreenSurface: children,
		host,
		strings,
	} as unknown as Parameters<typeof TerminalSurface>[0];

	return (
		<div aria-label={ariaLabel} data-testid="block-terminal" className="block-terminal-root h-full w-full">
			<TerminalSurface {...surfaceProps} />
		</div>
	);
}
