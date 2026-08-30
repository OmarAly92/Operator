import { useLayoutEffect, useRef, type ReactElement, type ReactNode } from "react";
import { LineEditor } from "@operator/terminal-editor";
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

	const hostClassName = className ? `terminal-host ${className}` : "terminal-host";
	const blockList = (
		<>
			<div ref={hostRef} className={hostClassName} />
			<div ref={editorHostRef} className="terminal-editor-host" />
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
