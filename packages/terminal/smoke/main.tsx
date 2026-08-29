import { StrictMode, useEffect, useRef, useState, type ReactElement } from "react";
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
const REPORT_URL = import.meta.env.TERMINAL_SMOKE_REPORT_URL;

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

async function reportReady(rows: number, runs: number): Promise<void> {
	if (!REPORT_URL) {
		return;
	}
	const url = new URL(REPORT_URL);
	if (
		url.protocol !== "http:" ||
		!["127.0.0.1", "localhost", "[::1]"].includes(url.hostname)
	) {
		throw new Error("terminal smoke reporter URL must use a loopback HTTP origin");
	}
	const response = await fetch(url, {
		method: "POST",
		headers: { "Content-Type": "application/json" },
		body: JSON.stringify({ status: "ready", text: "red caféplain", rows, runs }),
	});
	if (!response.ok) {
		throw new Error(`terminal smoke reporter returned ${response.status}`);
	}
}

function SmokeApp(): ReactElement {
	const [core, setCore] = useState<ReturnType<typeof createTerminalCore> | null>(null);
	const [error, setError] = useState<unknown>(null);
	const reported = useRef(false);

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
			if (block && rowNodes.length === 2 && runNodes.length === 3 && !reported.current) {
				reported.current = true;
				void reportReady(rowNodes.length, runNodes.length)
					.then(() => markReady(rowNodes.length, runNodes.length))
					.catch((caught: unknown) => {
						markFailed(caught);
						setError(caught);
					});
				return;
			}
			requestAnimationFrame(frame);
		};
		requestAnimationFrame(() => {
			requestAnimationFrame(frame);
		});
	}, [core, reported]);

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
