import type { LineEditorState, TerminalStrings } from "@operator/terminal-core";

export type PromptContext = Readonly<{
	cwd: string;
	gitBranch: string;
	lastExitCode: number | null;
	lastDurationMs: number | null;
	state: LineEditorState;
}>;

export function renderPromptRow(context: PromptContext, _strings: TerminalStrings): HTMLElement {
	const row = document.createElement("div");
	row.className = "terminal-editor-prompt";
	row.dataset.state = context.state;
	if (context.lastExitCode !== null) row.dataset.lastExit = String(context.lastExitCode);
	if (context.lastDurationMs !== null) row.dataset.lastDuration = String(context.lastDurationMs);

	const cwd = document.createElement("span");
	cwd.className = "terminal-editor-prompt-cwd";
	cwd.title = context.cwd;
	cwd.textContent = cwdLabel(context.cwd);
	row.append(cwd);

	if (context.gitBranch) {
		const branch = document.createElement("span");
		branch.className = "terminal-editor-prompt-branch";
		branch.textContent = context.gitBranch;
		row.append(branch);
	}

	const marker = document.createElement("span");
	marker.className = "terminal-editor-prompt-marker";
	marker.textContent = "❯";
	row.append(marker);
	return row;
}

function cwdLabel(cwd: string): string {
	if (!cwd) return "";
	if (cwd === "/") return "/";
	const segments = cwd.split("/").filter(Boolean);
	return segments.at(-1) ?? cwd;
}
