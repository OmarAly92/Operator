// wezterm/wezterm-gui/src/overlay/quickselect.rs compute_labels_for_alphabet
// (derived from tmux-thumbs, MIT, Copyright (c) 2019 Ferran Basora)
// wezterm/config/src/config.rs default_alphabet
export const DEFAULT_HINT_ALPHABET = "asdfqwerzxcvjklmiuopghtybn";

export function computeLabelsForAlphabet(alphabet: string, count: number): string[] {
	const letters = [...alphabet].map((letter) => letter.toLowerCase());
	const primary = [...letters];
	const secondary: string[] = [];
	while (primary.length + secondary.length < count) {
		const prefix = primary.pop();
		if (prefix === undefined) break;
		const take = count - primary.length - secondary.length;
		secondary.unshift(...letters.slice(0, Math.max(take, 0)).map((letter) => `${prefix}${letter}`));
	}
	return [...primary.slice(0, Math.max(count - secondary.length, 0)), ...secondary];
}
