import { useLayoutEffect, useRef, useState, type ReactElement, type ReactNode } from "react";
import { LineEditor, mapKey, passthroughFor } from "@operator/terminal-editor";
import { DomBlockRenderer, RERUN_EVENT } from "@operator/terminal-renderer-dom";
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

const WHEEL_LINE_HEIGHT_PX = 40;
const MAX_WHEEL_LINES = 10;

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
		return () => {
			blockHost.removeEventListener(RERUN_EVENT, onRerun);
			editor.dispose();
			renderer.dispose();
			editorRef.current = null;
			rendererRef.current = null;
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
			const columns = Math.max(1, Math.floor(blockHost.clientWidth / cellWidth));
			const rows = Math.max(1, Math.floor(blockHost.clientHeight / cellHeight));
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
		const appCursor = () => core.snapshot().applicationCursorKeys;
		const onKeyDown = (event: KeyboardEvent) => {
			const command = mapKey(event);
			if (!command) {
				return;
			}
			event.preventDefault();
			onSendRaw(passthroughFor(command, appCursor()));
		};
		const onWheel = (event: WheelEvent) => {
			const lines = Math.trunc(event.deltaY / WHEEL_LINE_HEIGHT_PX);
			if (lines === 0) {
				return;
			}
			event.preventDefault();
			const count = Math.min(Math.abs(lines), MAX_WHEEL_LINES);
			const snapshot = core.snapshot();
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

	const hostClassName = className ? `terminal-host ${className}` : "terminal-host";
	const blockList = (
		<>
			<div ref={hostRef} className={hostClassName} tabIndex={0} />
			<div ref={editorHostRef} className="terminal-editor-host" hidden={altActive} />
		</>
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
