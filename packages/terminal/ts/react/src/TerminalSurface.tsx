import { useLayoutEffect, useRef, type ReactElement } from "react";
import { DomBlockRenderer } from "@operator/terminal-renderer-dom";
import type { FontConfig, TerminalCore, TerminalTheme } from "@operator/terminal-core";

export interface TerminalSurfaceProps {
	core: TerminalCore;
	theme: TerminalTheme;
	font: FontConfig;
	className?: string;
}

export function TerminalSurface({ core, theme, font, className }: TerminalSurfaceProps): ReactElement {
	const hostRef = useRef<HTMLDivElement | null>(null);
	const rendererRef = useRef<DomBlockRenderer | null>(null);

	useLayoutEffect(() => {
		const host = hostRef.current;
		if (!host) {
			return;
		}
		const renderer = new DomBlockRenderer();
		renderer.mount(host, core);
		renderer.setTheme(theme);
		renderer.setFont(font);
		rendererRef.current = renderer;
		return () => {
			renderer.dispose();
			rendererRef.current = null;
		};
	}, [core]);

	useLayoutEffect(() => {
		rendererRef.current?.setTheme(theme);
	}, [theme]);

	useLayoutEffect(() => {
		rendererRef.current?.setFont(font);
	}, [font]);

	return <div ref={hostRef} className={className} />;
}
