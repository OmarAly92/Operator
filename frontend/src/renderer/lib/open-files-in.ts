import type { ExternalEditor } from "../../shared/operator-bridge";

export type OpenFilesIn = "system" | ExternalEditor;

export const EXTERNAL_EDITORS = [
	{ value: "vscode", label: "VS Code" },
	{ value: "cursor", label: "Cursor" },
	{ value: "zed", label: "Zed" },
] as const satisfies readonly { value: ExternalEditor; label: string }[];

export const openFilesInStorageKey = "opr.openFilesIn";
export const defaultOpenFilesIn: OpenFilesIn = "system";

function getLocalStorage() {
	if (typeof window === "undefined" || !window.localStorage) return null;
	return window.localStorage;
}

export function externalEditorLabel(editor: ExternalEditor): string {
	return EXTERNAL_EDITORS.find((option) => option.value === editor)?.label ?? editor;
}

export function readStoredOpenFilesIn(): OpenFilesIn {
	try {
		const stored = getLocalStorage()?.getItem(openFilesInStorageKey);
		const match = EXTERNAL_EDITORS.find((option) => option.value === stored);
		if (match) return match.value;
	} catch {
		return defaultOpenFilesIn;
	}
	return defaultOpenFilesIn;
}
