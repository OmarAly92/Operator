import { useLayoutEffect, useRef, type ReactElement, type ReactNode } from "react";
import { DomBlockRenderer } from "@operator/terminal-renderer-dom";
import type { FontConfig, TerminalCore, TerminalTheme } from "@operator/terminal-core";
import { AltScreenSlot } from "./AltScreenSlot.js";

export interface TerminalSurfaceProps {
	core: TerminalCore;
	theme: TerminalTheme;
	font: FontConfig;
	className?: string;
	altScreenSurface?: ReactNode;
	altScreenActive: boolean;
}

export function TerminalSurface({
	core,
	theme,
	font,
	className,
	altScreenSurface,
	altScreenActive,
}: TerminalSurfaceProps): ReactElement {
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

	const hostClassName = className ? `terminal-host ${className}` : "terminal-host";
	const host = <div ref={hostRef} className={hostClassName} />;
	return (
		<AltScreenSlot
			active={altScreenActive}
			surface={altScreenSurface}
			blockList={host}
		/>
	);
}
