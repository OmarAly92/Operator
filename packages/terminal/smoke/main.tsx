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
const IGNORE_INPUT = () => undefined;

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
			const block = main.querySelector('[data-terminal-block-id="0:0"]');
			const rowNodes = main.querySelectorAll("[data-terminal-row]");
			const runNodes = main.querySelectorAll("[data-terminal-run]");
			if (block && rowNodes.length === 3 && runNodes.length === 3 && !reported.current) {
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
			{core ? <TerminalSurface core={core} theme={warpDarkTheme} font={FONT} altScreenActive={false} onSend={IGNORE_INPUT} onSendRaw={IGNORE_INPUT} /> : null}
		</StrictMode>
	);
}

const FOLLOW_LINES = 500;

function FollowApp(): ReactElement | null {
	const [core, setCore] = useState<ReturnType<typeof createTerminalCore> | null>(null);

	useEffect(() => {
		let cancelled = false;
		const run = async () => {
			await initTerminalCoreFromUrl();
			if (cancelled) {
				return;
			}
			const next = createTerminalCore({ columns: 80, scrollback: 2000 });
			const lines: string[] = [];
			for (let i = 1; i <= FOLLOW_LINES; i += 1) {
				lines.push(`line-${i}`);
			}
			next.feed(new TextEncoder().encode(`${lines.join("\r\n")}\r\n`));
			setCore(next);
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
		requestAnimationFrame(() => {
			requestAnimationFrame(() => {
				const main = document.getElementById("terminal-follow-root");
				if (main) {
					main.dataset.terminalFollow = "ready";
					main.dataset.lineCount = String(FOLLOW_LINES);
				}
			});
		});
	}, [core]);

	return core ? <TerminalSurface core={core} theme={warpDarkTheme} font={FONT} altScreenActive={false} onSend={IGNORE_INPUT} onSendRaw={IGNORE_INPUT} /> : null;
}

function TierOneApp(): ReactElement | null {
	const [core, setCore] = useState<ReturnType<typeof createTerminalCore> | null>(null);
	const raw = useRef("");

	useEffect(() => {
		let cancelled = false;
		void initTerminalCoreFromUrl().then(() => {
			if (cancelled) return;
			const next = createTerminalCore({ columns: 80, scrollback: 100 });
			next.feed(
				new TextEncoder().encode(
					"\x1b]133;A\x07\x1b]133;B\x07echo tier-one\x1b]133;C\x07tier one\n\x1b]133;D;0\x07",
				),
			);
			setCore(next);
		});
		return () => {
			cancelled = true;
		};
	}, []);

	useEffect(() => {
		if (!core) return;
		requestAnimationFrame(() => {
			requestAnimationFrame(() => {
				const main = document.getElementById("terminal-tier-one-root");
				const editor = main?.querySelector<HTMLElement>(".terminal-editor");
				if (!main || !editor) return;
				editor.dispatchEvent(new KeyboardEvent("keydown", { key: "x", bubbles: true }));
				editor.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
				main.dataset.lineEditorState = core.lineEditorState();
				main.dataset.editorReadOnly = editor.getAttribute("aria-readonly") ?? "";
				main.dataset.rawInput = raw.current.replaceAll("\r", "\\r");
				main.dataset.terminalTierOne = "ready";
			});
		});
	}, [core]);

	return core ? (
		<TerminalSurface
			core={core}
			theme={warpDarkTheme}
			font={FONT}
			altScreenActive={false}
			onSend={IGNORE_INPUT}
			onSendRaw={(data) => {
				raw.current += data;
			}}
		/>
	) : null;
}

function AltScreenApp(): ReactElement | null {
	const [core, setCore] = useState<ReturnType<typeof createTerminalCore> | null>(null);

	useEffect(() => {
		let cancelled = false;
		void initTerminalCoreFromUrl().then(() => {
			if (cancelled) return;
			const next = createTerminalCore({ columns: 80, scrollback: 100 });
			next.feed(
				new TextEncoder().encode(
					"\x1b]133;A\x07\x1b]133;B\x07ls\x1b]133;C\x07file.txt\n\x1b]133;D;0\x07",
				),
			);
			setCore(next);
		});
		return () => {
			cancelled = true;
		};
	}, []);

	useEffect(() => {
		if (!core) return;
		requestAnimationFrame(() => {
			requestAnimationFrame(() => {
				const main = document.getElementById("terminal-alt-root");
				if (!main) return;
				const blocks = Array.from(main.querySelectorAll<HTMLElement>("[data-terminal-block-id]"));
				const beforeIds = blocks.map((node) => node.dataset.terminalBlockId ?? "");
				const beforeCount = blocks.length;
				core.feed(new TextEncoder().encode("\x1b[?1049h"));
				core.feed(
					new TextEncoder().encode(
						"\x1b]133;A\x07\x1b]133;B\x07garbage\x1b]133;C\x07mark-shaped bytes inside the alt screen\x1b]133;D;7\x07",
					),
				);
				core.feed(new TextEncoder().encode("\x1b[?1049l"));
				requestAnimationFrame(() => {
					requestAnimationFrame(() => {
						const blocksAfter = Array.from(
							main.querySelectorAll<HTMLElement>("[data-terminal-block-id]"),
						);
						const afterIds = blocksAfter.map((node) => node.dataset.terminalBlockId ?? "");
						const surface = main.querySelector("[data-terminal-alt-surface]") as HTMLElement | null;
						const hidden = surface === null || surface.hidden;
						main.dataset.terminalAltShred = "ready";
						main.dataset.terminalAltShredBefore = beforeIds.join(",");
						main.dataset.terminalAltShredAfter = afterIds.join(",");
						main.dataset.terminalAltShredBeforeCount = String(beforeCount);
						main.dataset.terminalAltShredAfterCount = String(blocksAfter.length);
						main.dataset.terminalAltShredSurfaceHidden = String(hidden);
					});
				});
			});
		});
	}, [core]);

	return core ? <TerminalSurface core={core} theme={warpDarkTheme} font={FONT} altScreenActive={false} onSend={IGNORE_INPUT} onSendRaw={IGNORE_INPUT} /> : null;
}

function AltScrollApp(): ReactElement | null {
	const [core, setCore] = useState<ReturnType<typeof createTerminalCore> | null>(null);

	useEffect(() => {
		let cancelled = false;
		void initTerminalCoreFromUrl().then(() => {
			if (cancelled) return;
			const next = createTerminalCore({ columns: 40, scrollback: 100 });
			next.feed(new TextEncoder().encode("\x1b[?1049h\x1b[2;1Hinside-alt-stay"));
			setCore(next);
		});
		return () => {
			cancelled = true;
		};
	}, []);

	useEffect(() => {
		if (!core) return;
		requestAnimationFrame(() => {
			requestAnimationFrame(() => {
				const main = document.getElementById("terminal-alt-scroll-root");
				if (!main) return;
				const host = main.querySelector<HTMLElement>(".terminal-host");
				const surface = main.querySelector("[data-terminal-alt-surface]") as HTMLElement | null;
				main.dataset.terminalAltScroll = "ready";
				main.dataset.terminalAltScrollHostHeight = String(host?.clientHeight ?? 0);
				main.dataset.terminalAltScrollOverflow = host?.style.overflow ?? "";
				main.dataset.terminalAltScrollSurfaceVisible =
					surface === null ? "missing" : String(!surface.hidden);
			});
		});
	}, [core]);

	return core ? <TerminalSurface core={core} theme={warpDarkTheme} font={FONT} altScreenActive={false} onSend={IGNORE_INPUT} onSendRaw={IGNORE_INPUT} /> : null;
}

function FallbackApp(): ReactElement | null {
	const [core, setCore] = useState<ReturnType<typeof createTerminalCore> | null>(null);

	useEffect(() => {
		let cancelled = false;
		void initTerminalCoreFromUrl().then(() => {
			if (cancelled) return;
			const next = createTerminalCore({ columns: 20, scrollback: 100 });
			next.feed(new TextEncoder().encode("\x1b[?1049h\x1b[2;3Hfrom-fallback"));
			setCore(next);
		});
		return () => {
			cancelled = true;
		};
	}, []);

	useEffect(() => {
		if (!core) return;
		requestAnimationFrame(() => {
			requestAnimationFrame(() => {
				const main = document.getElementById("terminal-fallback-root");
				if (!main) return;
				const slot = main.querySelector(".terminal-fallback-surface");
				const slotVisible = slot ? !slot.hidden : false;
				main.dataset.terminalFallback = "ready";
				main.dataset.terminalFallbackVisible = String(slotVisible);
			});
		});
	}, [core]);

	return core ? (
		<TerminalSurface
			core={core}
			theme={warpDarkTheme}
			font={FONT}
			altScreenActive={true}
			altScreenSurface={<div className="terminal-fallback-surface" data-testid="terminal-fallback-surface">fallback-xterm-slot</div>}
			onSend={IGNORE_INPUT}
			onSendRaw={IGNORE_INPUT}
		/>
	) : null;
}

function PaddingApp(): ReactElement | null {
	const [core, setCore] = useState<ReturnType<typeof createTerminalCore> | null>(null);

	useEffect(() => {
		let cancelled = false;
		void initTerminalCoreFromUrl().then(() => {
			if (cancelled) return;
			const next = createTerminalCore({ columns: 40, scrollback: 100 });
			next.feed(new TextEncoder().encode("padded"));
			setCore(next);
		});
		return () => {
			cancelled = true;
		};
	}, []);

	useEffect(() => {
		if (!core) return;
		requestAnimationFrame(() => {
			requestAnimationFrame(() => {
				const main = document.getElementById("terminal-padding-root");
				const surface = main?.querySelector<HTMLElement>(".terminal-surface");
				const host = main?.querySelector<HTMLElement>(".terminal-host");
				const editor = main?.querySelector<HTMLElement>(".terminal-editor-host");
				if (!main || !surface || !host) return;
				const surfaceRect = surface.getBoundingClientRect();
				const hostRect = host.getBoundingClientRect();
				const editorHeight = editor ? editor.getBoundingClientRect().height : 0;
				main.dataset.terminalPaddingInsetLeft = String(Math.round(hostRect.left - surfaceRect.left));
				main.dataset.terminalPaddingInsetTop = String(Math.round(hostRect.top - surfaceRect.top));
				main.dataset.terminalPaddingInsetRight = String(Math.round(surfaceRect.right - hostRect.right));
				// The editor is a sibling of the host inside the surface. If the host
				// claims the surface's full height the editor is laid out past the
				// bottom edge, the pane clips the overflow, and the first row of the
				// transcript is cut off with no way to scroll up to it.
				main.dataset.terminalPaddingOverflow = String(
					Math.round(hostRect.height + editorHeight - surfaceRect.height),
				);
				// Warp anchors its block list to the bottom of the pane: the first
				// command you run appears at the bottom edge and earlier output
				// scrolls up off the top. Content shorter than the viewport must
				// therefore sit against the bottom, not the top.
				// Measured against the block's own edge, not its last row: the block
				// reserves a line of padding below its output, so the row legitimately
				// stops short of the pane bottom.
				const blocks = main.querySelectorAll<HTMLElement>("[data-terminal-block-id]");
				const lastBlock = blocks[blocks.length - 1];
				main.dataset.terminalPaddingBottomGap = String(
					lastBlock ? Math.round(hostRect.bottom - lastBlock.getBoundingClientRect().bottom) : -1,
				);
				main.dataset.terminalPaddingHostHeight = String(Math.round(hostRect.height));
				main.dataset.terminalPaddingSurfaceHeight = String(Math.round(surfaceRect.height));
				main.dataset.terminalPaddingEditorHeight = String(Math.round(editorHeight));
				main.dataset.terminalPadding = "ready";
			});
		});
	}, [core]);

	return core ? <TerminalSurface core={core} theme={warpDarkTheme} font={FONT} altScreenActive={false} onSend={IGNORE_INPUT} onSendRaw={IGNORE_INPUT} /> : null;
}

function PinnedHeaderApp(): ReactElement | null {
	const [core, setCore] = useState<ReturnType<typeof createTerminalCore> | null>(null);

	useEffect(() => {
		let cancelled = false;
		void initTerminalCoreFromUrl().then(() => {
			if (cancelled) return;
			const next = createTerminalCore({ columns: 20, scrollback: 2000 });
			const start = `\x1b]133;A\x07\x1b]133;B\x07\x1b]7000;v=1; cmd=tall-cmd\x07\x1b]133;C\x07`;
			const body = Array.from({ length: 200 }, (_unused, i) => `row-${i + 1}`).join("\n");
			const end = `\x1b]133;D;0\x07`;
			next.feed(new TextEncoder().encode(`${start}${body}${end}`));
			const tail = `\x1b]133;A\x07\x1b]133;B\x07\x1b]7000;v=1; cmd=tail-cmd\x07\x1b]133;C\x07done\x1b]133;D;0\x07`;
			next.feed(new TextEncoder().encode(tail));
			setCore(next);
		});
		return () => {
			cancelled = true;
		};
	}, []);

	useEffect(() => {
		if (!core) return;
		const frame = (): void => {
			const main = document.getElementById("terminal-pinned-root");
			if (!main) return;
			const host = main.querySelector<HTMLElement>(".terminal-host");
			const pinned = main.querySelector<HTMLElement>('[data-testid="terminal-pinned-header"]');
			if (!host || !pinned) {
				requestAnimationFrame(frame);
				return;
			}
			host.scrollTop = Math.max(0, Math.round(host.scrollHeight / 2) - Math.round(host.clientHeight / 2));
			host.dispatchEvent(new Event("scroll"));
			requestAnimationFrame(() => {
				requestAnimationFrame(() => {
					const tall = main.querySelector('[data-terminal-block-id="0:0"]') as HTMLElement | null;
					const tallRect = tall?.getBoundingClientRect();
					main.dataset.terminalPinned = "ready";
					main.dataset.terminalPinnedHidden = String(pinned.hidden);
					main.dataset.terminalPinnedText = pinned.textContent ?? "";
					main.dataset.terminalPinnedStatus = pinned.dataset.blockStatus ?? "";
					main.dataset.terminalPinnedTallTop = tallRect ? String(Math.round(tallRect.top)) : "";
					main.dataset.terminalPinnedHeaderTop = String(Math.round(pinned.getBoundingClientRect().top));
				});
			});
		};
		requestAnimationFrame(() => {
			requestAnimationFrame(frame);
		});
	}, [core]);

	return core ? <TerminalSurface core={core} theme={warpDarkTheme} font={FONT} altScreenActive={false} onSend={IGNORE_INPUT} onSendRaw={IGNORE_INPUT} /> : null;
}

const root = document.getElementById("terminal-smoke-root");
if (!root) {
	throw new Error("missing #terminal-smoke-root");
}
createRoot(root).render(<SmokeApp />);

const followRoot = document.getElementById("terminal-follow-root");
if (!followRoot) {
	throw new Error("missing #terminal-follow-root");
}
createRoot(followRoot).render(<FollowApp />);

const tierOneRoot = document.getElementById("terminal-tier-one-root");
if (!tierOneRoot) {
	throw new Error("missing #terminal-tier-one-root");
}
createRoot(tierOneRoot).render(<TierOneApp />);

const altRoot = document.getElementById("terminal-alt-root");
if (!altRoot) {
	throw new Error("missing #terminal-alt-root");
}
createRoot(altRoot).render(<AltScreenApp />);

const fallbackRoot = document.getElementById("terminal-fallback-root");
if (!fallbackRoot) {
	throw new Error("missing #terminal-fallback-root");
}
createRoot(fallbackRoot).render(<FallbackApp />);

const altScrollRoot = document.getElementById("terminal-alt-scroll-root");
if (!altScrollRoot) {
	throw new Error("missing #terminal-alt-scroll-root");
}
createRoot(altScrollRoot).render(<AltScrollApp />);

const paddingRoot = document.getElementById("terminal-padding-root");
if (!paddingRoot) {
	throw new Error("missing #terminal-padding-root");
}
createRoot(paddingRoot).render(<PaddingApp />);

const pinnedRoot = document.getElementById("terminal-pinned-root");
if (!pinnedRoot) {
	throw new Error("missing #terminal-pinned-root");
}
createRoot(pinnedRoot).render(<PinnedHeaderApp />);
