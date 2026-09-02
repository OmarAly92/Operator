import { useCallback, useLayoutEffect, useRef, useState, type ReactElement, type ReactNode } from "react";
import { encodeKey, LineEditor } from "@operator/terminal-editor";
import { createFindBar, DomBlockRenderer, RERUN_EVENT, type FindBar } from "@operator/terminal-renderer-dom";
import {
	decodeBlocks,
	defaultStrings,
	type FontConfig,
	type HostCapabilities,
	type TerminalCore,
	type TerminalStrings,
	type TerminalTheme,
} from "@operator/terminal-core";
import { AltScreenSlot } from "./AltScreenSlot.js";

export interface TerminalSurfaceProps {
	core: TerminalCore;
	theme: TerminalTheme;
	font: FontConfig;
	className?: string;
	altScreenSurface?: ReactNode;
	altScreenActive: boolean;
	host?: HostCapabilities;
	strings?: TerminalStrings;
	onSend(text: string): void;
	onSendRaw(data: string): void;
	onGeometry?: (columns: number, rows: number) => void;
}

// macOS hands a native app an already-accelerated scroll delta: a flick reports
// tens of pixels per event and keeps reporting through a momentum tail. The
// WebView hands us the raw gesture instead -- measured on a trackpad, ~1-3px per
// event at ~115 events/sec, with no tail -- so a flick and a crawl travel nearly
// the same distance and the alt screen advances a row at a time. Scale the delta
// by gesture velocity to restore the curve the platform withheld. Below the
// reference speed the gain is 1, so slow, deliberate scrolling stays exact.
const ACCEL_REFERENCE_PX_PER_SEC = 100;
const ACCEL_MAX_GAIN = 6;
// A gap this long means fingers left the trackpad; the next event starts a new
// gesture rather than inheriting the old one's speed.
const GESTURE_IDLE_MS = 200;
// Velocity is averaged over recent events: a single jittery sample should not
// launch the viewport. Averaging up from zero also means a gesture has to
// sustain speed before it accelerates, so a short nudge stays a short nudge.
const VELOCITY_SMOOTHING = 0.3;
// Events closer together than this are one frame's worth of coalesced motion,
// not evidence of speed; dividing by their sub-millisecond gap would report
// thousands of pixels per second for an ordinary scroll.
const MIN_VELOCITY_SAMPLE_MS = 4;

function accelerationGain(velocityPxPerSec: number): number {
	const gain = velocityPxPerSec / ACCEL_REFERENCE_PX_PER_SEC;
	return Math.min(Math.max(gain, 1), ACCEL_MAX_GAIN);
}

export function TerminalSurface({
	core,
	theme,
	font,
	className,
	altScreenSurface,
	altScreenActive,
	host,
	strings = defaultStrings,
	onSend,
	onSendRaw,
	onGeometry,
}: TerminalSurfaceProps): ReactElement {
	const hostRef = useRef<HTMLDivElement | null>(null);
	const editorHostRef = useRef<HTMLDivElement | null>(null);
	const rendererRef = useRef<DomBlockRenderer | null>(null);
	const editorRef = useRef<LineEditor | null>(null);
	const findBarRef = useRef<FindBar | null>(null);

	useLayoutEffect(() => {
		const blockHost = hostRef.current;
		const editorHost = editorHostRef.current;
		if (!blockHost || !editorHost) {
			return;
		}
		const renderer = new DomBlockRenderer();
		renderer.mount(blockHost, core);
		renderer.setTheme(theme);
		renderer.setFont(font);
		renderer.setHostCapabilities(host ?? null);
		const editor = new LineEditor();
		editor.mount(editorHost, core, { send: onSend, sendRaw: onSendRaw });
		editor.setTheme(theme);
		editor.setFont(font);
		editor.setStrings(strings);
		const findBar = createFindBar({
			core,
			renderer,
			host: {
				scrollToBlock: (id, align) => renderer.scrollToBlock(id, align),
				invalidate: (range) => renderer.invalidate(range),
				afterRepaint: (listener) => renderer.onPaint(listener),
			},
			strings,
		});
		findBar.mount(blockHost);
		const onRerun = (event: Event) => {
			const blockId = (event as CustomEvent<{ blockId?: string }>).detail?.blockId;
			if (!blockId) return;
			const block = decodeBlocks(core.snapshot()).find((candidate) => candidate.id === blockId);
			if (!block) return;
			editor.setText(block.command);
			editor.focus();
		};
		blockHost.addEventListener(RERUN_EVENT, onRerun);
		rendererRef.current = renderer;
		editorRef.current = editor;
		findBarRef.current = findBar;
		return () => {
			blockHost.removeEventListener(RERUN_EVENT, onRerun);
			findBar.dispose();
			editor.dispose();
			renderer.dispose();
			editorRef.current = null;
			rendererRef.current = null;
			findBarRef.current = null;
		};
	}, [core, onSend, onSendRaw]);

	useLayoutEffect(() => {
		rendererRef.current?.setTheme(theme);
		editorRef.current?.setTheme(theme);
	}, [theme]);

	useLayoutEffect(() => {
		rendererRef.current?.setFont(font);
		editorRef.current?.setFont(font);
	}, [font]);

	useLayoutEffect(() => {
		rendererRef.current?.setHostCapabilities(host ?? null);
	}, [host]);

	useLayoutEffect(() => {
		editorRef.current?.setStrings(strings);
	}, [strings]);

	useLayoutEffect(() => {
		const blockHost = hostRef.current;
		const renderer = rendererRef.current;
		if (!blockHost || !renderer) {
			return;
		}
		let lastColumns = 0;
		let lastRows = 0;
		const apply = () => {
			if (blockHost.clientWidth <= 0 || blockHost.clientHeight <= 0) {
				return;
			}
			const { cellWidth, cellHeight } = renderer.measure();
			if (cellWidth <= 0 || cellHeight <= 0) {
				return;
			}
			// Rows are laid out inside the block's padding, so the grid gets the
			// space left after it -- not the host's full box.
			const inset = renderer.blockContentInset();
			const columns = Math.max(1, Math.floor((blockHost.clientWidth - inset.x) / cellWidth));
			const rows = Math.max(1, Math.floor((blockHost.clientHeight - inset.y) / cellHeight));
			if (columns === lastColumns && rows === lastRows) {
				return;
			}
			lastColumns = columns;
			lastRows = rows;
			core.resize(columns, rows);
			onGeometry?.(columns, rows);
		};
		apply();
		if (typeof ResizeObserver !== "function") {
			return;
		}
		const observer = new ResizeObserver(apply);
		observer.observe(blockHost);
		return () => observer.disconnect();
	}, [core, onGeometry]);

	const [altActive, setAltActive] = useState(false);
	useLayoutEffect(() => {
		const read = () => setAltActive(core.snapshot().altScreen !== null);
		read();
		return core.onChange(read);
	}, [core]);

	useLayoutEffect(() => {
		const blockHost = hostRef.current;
		if (!blockHost || !altActive) {
			return;
		}
		let pendingWheelLines = 0;
		let velocityPxPerSec = 0;
		let lastWheelAt = 0;
		const appCursor = () => core.snapshot().applicationCursorKeys;
		const onKeyDown = (event: KeyboardEvent) => {
			const data = encodeKey(event, appCursor());
			if (data === null) {
				return;
			}
			event.preventDefault();
			onSendRaw(data);
		};
		const sampleVelocity = (deltaY: number): number => {
			const now = performance.now();
			const elapsed = now - lastWheelAt;
			if (elapsed > GESTURE_IDLE_MS) {
				lastWheelAt = now;
				velocityPxPerSec = 0;
				return 0;
			}
			if (elapsed < MIN_VELOCITY_SAMPLE_MS) {
				return velocityPxPerSec;
			}
			lastWheelAt = now;
			const sample = (Math.abs(deltaY) / elapsed) * 1000;
			velocityPxPerSec += (sample - velocityPxPerSec) * VELOCITY_SMOOTHING;
			return velocityPxPerSec;
		};
		const onWheel = (event: WheelEvent) => {
			event.preventDefault();
			const snapshot = core.snapshot();
			const measuredCellHeight = rendererRef.current?.measure().cellHeight ?? 0;
			const deltaLines =
				event.deltaMode === WheelEvent.DOM_DELTA_LINE
					? event.deltaY
					: event.deltaMode === WheelEvent.DOM_DELTA_PAGE
						? event.deltaY * (snapshot.altScreen?.rows ?? 1)
						: measuredCellHeight > 0
							? (event.deltaY * accelerationGain(sampleVelocity(event.deltaY))) / measuredCellHeight
							: 0;
			if (!Number.isFinite(deltaLines)) return;
			pendingWheelLines += deltaLines;
			const lines = Math.trunc(pendingWheelLines);
			pendingWheelLines -= lines;
			if (lines === 0) return;
			const count = Math.abs(lines);
			if (snapshot.sgrMouse && snapshot.mouseTracking) {
				const { column, row } = pointerCell(blockHost, event, rendererRef.current);
				const button = lines > 0 ? 65 : 64;
				onSendRaw(`\x1b[<${button};${column};${row}M`.repeat(count));
				return;
			}
			const prefix = appCursor() ? "\x1bO" : "\x1b[";
			const key = lines > 0 ? "B" : "A";
			onSendRaw(`${prefix}${key}`.repeat(count));
		};
		blockHost.addEventListener("keydown", onKeyDown);
		blockHost.addEventListener("wheel", onWheel, { passive: false });
		blockHost.focus();
		return () => {
			blockHost.removeEventListener("keydown", onKeyDown);
			blockHost.removeEventListener("wheel", onWheel);
		};
	}, [altActive, core, onSendRaw]);

	useLayoutEffect(() => {
		const findBar = findBarRef.current;
		if (!findBar) return;
		const onKeyDown = (event: KeyboardEvent) => {
			if ((event.metaKey || event.ctrlKey) && (event.key === "f" || event.key === "F")) {
				event.preventDefault();
				findBar.open();
			}
		};
		document.addEventListener("keydown", onKeyDown);
		return () => document.removeEventListener("keydown", onKeyDown);
	}, []);

	// Clicking the transcript belongs to the editor, the way clicking anywhere in
	// a terminal keeps you typing at the prompt. Without this the click lands on
	// the host (or nowhere) and the next keystroke goes nowhere. Runs on click,
	// not mousedown, so a drag-select is left alone.
	const focusEditorFromHost = useCallback(() => {
		if (altActive) return;
		const selection = document.getSelection();
		if (selection && !selection.isCollapsed) return;
		editorRef.current?.focus();
	}, [altActive]);

	const hostClassName = className ? `terminal-host ${className}` : "terminal-host";
	const blockList = (
		<div className="terminal-surface">
			{/* tabindex only while the alt-screen handler below is bound. In the
			    normal buffer the editor is the input surface, and a focusable host
			    steals the click: nothing handles keys there, so typing is dropped,
			    arrows scroll the list, and the first keypress paints a focus ring
			    around the whole terminal. */}
			<div
				ref={hostRef}
				className={hostClassName}
				onClick={focusEditorFromHost}
				tabIndex={altActive ? 0 : undefined}
			/>
			<div ref={editorHostRef} className="terminal-editor-host" hidden={altActive} />
		</div>
	);
	return (
		<AltScreenSlot
			active={altScreenActive}
			surface={altScreenSurface}
			blockList={blockList}
		/>
	);
}

function pointerCell(
	host: HTMLElement,
	event: WheelEvent,
	renderer: DomBlockRenderer | null,
): { column: number; row: number } {
	const metrics = renderer?.measure();
	if (!metrics || metrics.cellWidth <= 0 || metrics.cellHeight <= 0) {
		return { column: 1, row: 1 };
	}
	const bounds = host.getBoundingClientRect();
	const column = Math.floor((event.clientX - bounds.left) / metrics.cellWidth) + 1;
	const row = Math.floor((event.clientY - bounds.top) / metrics.cellHeight) + 1;
	return { column: Math.max(1, column), row: Math.max(1, row) };
}
