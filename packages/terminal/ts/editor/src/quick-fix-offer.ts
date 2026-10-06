import { decodeBlocks, type BlockView, type TerminalCore } from "@operator/terminal-core";
import { findQuickFix, QUICK_FIX_WINDOW_LIMIT, type QuickFix, type QuickFixRule } from "./quick-fix.js";

const OUTPUT_LINES = QUICK_FIX_WINDOW_LIMIT * 2 + 1;

function lastSettled(blocks: readonly BlockView[]): number {
	for (let index = blocks.length - 1; index >= 0; index -= 1) {
		if (blocks[index]!.state !== "running") return index;
	}
	return -1;
}

export class QuickFixOffer {
	private rules: readonly QuickFixRule[] = [];
	private seen: string | null = null;
	private current: QuickFix | null = null;

	setRules(rules: readonly QuickFixRule[]): void {
		this.rules = rules;
		if (rules.length === 0) this.current = null;
	}

	reset(core: TerminalCore): void {
		const blocks = decodeBlocks(core.snapshot());
		this.seen = blocks[lastSettled(blocks)]?.id ?? null;
		this.current = null;
	}

	observe(core: TerminalCore): void {
		const snapshot = core.snapshot();
		if (snapshot.altScreen !== null) return;
		const blocks = decodeBlocks(snapshot);
		const index = lastSettled(blocks);
		if (blocks.slice(index + 1).some((block) => block.command.length > 0)) {
			this.current = null;
			return;
		}
		const block = blocks[index];
		if (!block || block.id === this.seen) return;
		this.seen = block.id;
		this.current = null;
		if (this.rules.length === 0 || block.state !== "finished" || block.source === "synthetic") return;
		this.current = findQuickFix(this.rules, {
			command: block.command,
			exitCode: block.exitCode,
			output: () => (core.readBlockOutput(block.id, { maxLines: OUTPUT_LINES }) ?? "").split("\n"),
		});
	}

	fix(): QuickFix | null {
		return this.current;
	}

	dismiss(): void {
		this.current = null;
	}
}

export function renderQuickFixRow(fix: QuickFix, label: string, useLabel: string, use: () => void): HTMLElement {
	const row = document.createElement("div");
	row.className = "terminal-editor-quick-fix";
	row.dataset.quickFix = fix.ruleId;
	const title = document.createElement("span");
	title.className = "terminal-editor-quick-fix-label";
	title.textContent = label;
	const command = document.createElement("span");
	command.className = "terminal-editor-quick-fix-command";
	command.textContent = fix.command;
	command.title = fix.command;
	const button = document.createElement("button");
	button.type = "button";
	button.className = "terminal-editor-quick-fix-use";
	button.textContent = useLabel;
	button.setAttribute("aria-label", `${useLabel}: ${fix.command}`);
	button.addEventListener("mousedown", (event) => event.preventDefault());
	button.addEventListener("click", (event) => {
		event.preventDefault();
		event.stopPropagation();
		use();
	});
	row.append(title, command, button);
	return row;
}
