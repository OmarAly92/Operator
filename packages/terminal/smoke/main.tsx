import { StrictMode, useEffect, useState, type ReactElement } from "react";
import { createRoot } from "react-dom/client";
import {
	TerminalSurface,
	createTerminalCore,
	initTerminalCoreFromUrl,
	warpDarkTheme,
} from "@operator/terminal-react";

const FONT = {
	family: "ui-monospace, monospace",
	sizePx: 14,
	lineHeight: 1.2,
	weight: 400,
	letterSpacingPx: 0,
	ligatures: false,
} as const;

const INPUT = "\x1b[31mred\x1b[0m café\r\nplain";

function markReady(rows: number, runs: number): void {
	const main = document.getElementById("terminal-smoke-root");
	if (!main) {
		return;
	}
	main.dataset.terminalSmoke = "ready";
	main.dataset.rowCount = String(rows);
	main.dataset.runCount = String(runs);
}

function markFailed(error: unknown): void {
	const main = document.getElementById("terminal-smoke-root");
	if (!main) {
		return;
	}
	main.dataset.terminalSmoke = "failed";
	main.textContent = error instanceof Error ? error.message : String(error);
}

function SmokeApp(): ReactElement {
	const [core, setCore] = useState<ReturnType<typeof createTerminalCore> | null>(null);
	const [error, setError] = useState<unknown>(null);

	useEffect(() => {
		let cancelled = false;
		const run = async () => {
			try {
				await initTerminalCoreFromUrl();
				if (cancelled) {
					return;
				}
				const next = createTerminalCore({ columns: 16, scrollback: 100 });
				next.feed(new TextEncoder().encode(INPUT));
				setCore(next);
			} catch (caught) {
				if (!cancelled) {
					setError(caught);
				}
			}
		};
		void run();
		return () => {
			cancelled = true;
		};
	}, []);

	useEffect(() => {
		if (!core) {
			return;
		}
		const frame = (): void => {
			const main = document.getElementById("terminal-smoke-root");
			if (!main) {
				return;
			}
			const block = main.querySelector('[data-terminal-block-id="synthetic-0"]');
			const rowNodes = main.querySelectorAll("[data-terminal-row]");
			const runNodes = main.querySelectorAll("[data-terminal-run]");
			if (block && rowNodes.length === 2 && runNodes.length === 3) {
				markReady(rowNodes.length, runNodes.length);
				return;
			}
			requestAnimationFrame(frame);
		};
		requestAnimationFrame(() => {
			requestAnimationFrame(frame);
		});
	}, [core]);

	if (error) {
		markFailed(error);
		throw error;
	}

	return (
		<StrictMode>
			{core ? <TerminalSurface core={core} theme={warpDarkTheme} font={FONT} /> : null}
		</StrictMode>
	);
}

const root = document.getElementById("terminal-smoke-root");
if (!root) {
	throw new Error("missing #terminal-smoke-root");
}
createRoot(root).render(<SmokeApp />);
