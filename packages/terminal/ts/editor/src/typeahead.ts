import type { TerminalCore } from "@operator/terminal-core";

export const TYPEAHEAD_MAX_CHARS = 256;

export const CLEAR_SHELL_LINE = "\x15";

const CONTROL = /[\u0000-\u001f\u007f-\u009f]/u;

export function acceptTypeahead(text: string): string | null {
	if (text === "") return null;
	if ([...text].length > TYPEAHEAD_MAX_CHARS) return null;
	if (CONTROL.test(text)) return null;
	return text;
}

export class TypeaheadGate {
	private typed = false;

	reset(): void {
		this.typed = false;
	}

	noteSent(data: string): void {
		if (data !== "") this.typed = true;
	}

	take(core: TerminalCore): string | null {
		const reported = core.takeTypeahead();
		if (reported === "") return null;
		const accepted = this.typed ? acceptTypeahead(reported) : null;
		this.typed = false;
		return accepted;
	}
}
