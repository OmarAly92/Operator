import type { BlockView, TerminalStrings } from "@operator/terminal-core";

const CLASS_HEADER = "terminal-block-header";
const CLASS_DOT = "terminal-block-status-dot";
const CLASS_COMMAND = "terminal-block-command";
const CLASS_CWD = "terminal-block-cwd";
const CLASS_BRANCH = "terminal-block-branch";
const CLASS_DURATION = "terminal-block-duration";
const CLASS_EXIT = "terminal-block-exit";

function statusFor(block: BlockView): "running" | "succeeded" | "failed" | "abandoned" | "plain" {
	if (block.source === "synthetic") return "plain";
	if (block.state === "running") return "running";
	if (block.state === "abandoned") return "abandoned";
	if (block.exitCode === null) return "running";
	if (block.exitCode === 0) return "succeeded";
	return "failed";
}

function shortenCwd(cwd: string, home: string | null): string {
	if (home && cwd === home) return "~";
	if (home && cwd.startsWith(`${home}/`)) return `~${cwd.slice(home.length)}`;
	return cwd;
}

function formatDuration(ms: number | null): string | null {
	if (ms === null) return null;
	if (ms < 1000) return `${ms}ms`;
	const totalSeconds = Math.round(ms / 1000);
	if (totalSeconds < 60) return `${totalSeconds}s`;
	const minutes = Math.floor(totalSeconds / 60);
	const seconds = totalSeconds % 60;
	if (minutes < 60) {
		return seconds === 0 ? `${minutes}m` : `${minutes}m ${seconds}s`;
	}
	const hours = Math.floor(minutes / 60);
	const restMinutes = minutes % 60;
	return restMinutes === 0 ? `${hours}h` : `${hours}h ${restMinutes}m`;
}

function buildDot(status: ReturnType<typeof statusFor>): HTMLElement {
	const dot = document.createElement("span");
	dot.className = CLASS_DOT;
	dot.dataset.terminalBlockStatus = status;
	dot.setAttribute("aria-hidden", "true");
	return dot;
}

function buildCommand(text: string): HTMLElement {
	const node = document.createElement("span");
	node.className = CLASS_COMMAND;
	node.textContent = text;
	return node;
}

function buildCwd(cwd: string, home: string | null): HTMLElement | null {
	const shortened = shortenCwd(cwd, home);
	if (shortened.length === 0) return null;
	const node = document.createElement("span");
	node.className = CLASS_CWD;
	node.textContent = shortened;
	return node;
}

function buildBranch(branch: string): HTMLElement | null {
	if (branch.length === 0) return null;
	const node = document.createElement("span");
	node.className = CLASS_BRANCH;
	node.textContent = branch;
	return node;
}

function buildDuration(ms: number | null, exitCode: number | null): HTMLElement | null {
	const formatted = formatDuration(ms);
	if (formatted === null) return null;
	const node = document.createElement("span");
	node.className = CLASS_DURATION;
	node.textContent = formatted;
	if (exitCode !== null) {
		const exit = document.createElement("span");
		exit.className = CLASS_EXIT;
		exit.textContent = `exit ${exitCode}`;
		node.append(exit);
	}
	return node;
}

export function renderBlockHeader(
	block: BlockView,
	strings: TerminalStrings,
	opts: { home?: string | null } = {},
): HTMLElement {
	const header = document.createElement("header");
	header.className = CLASS_HEADER;
	const status = statusFor(block);
	header.dataset.blockStatus = status;

	if (status === "plain") {
		return header;
	}

	header.append(renderBlockHeaderContent(block, opts.home ?? null));
	header.setAttribute("aria-label", statusLabel(status, strings));
	return header;
}

export function renderBlockHeaderContent(block: BlockView, home: string | null): DocumentFragment {
	const status = statusFor(block);
	const fragment = document.createDocumentFragment();
	fragment.append(buildDot(status));
	fragment.append(buildCommand(block.command));
	const cwd = buildCwd(block.cwd, home);
	if (cwd) fragment.append(cwd);
	const branch = buildBranch(block.gitBranch);
	if (branch) fragment.append(branch);
	const duration = buildDuration(block.durationMs, status === "failed" ? block.exitCode : null);
	if (duration) fragment.append(duration);
	return fragment;
}

export function blockHeaderStatus(block: BlockView): "running" | "succeeded" | "failed" | "abandoned" | "plain" {
	return statusFor(block);
}

export function statusLabel(status: "running" | "succeeded" | "failed" | "abandoned" | "plain", strings: TerminalStrings): string {
	switch (status) {
		case "running":
			return strings.blockRunning;
		case "succeeded":
			return strings.blockSucceeded;
		case "failed":
			return strings.blockFailed;
		case "abandoned":
			return strings.blockAbandoned;
		case "plain":
			return strings.shellBlocksUnavailable;
	}
}
