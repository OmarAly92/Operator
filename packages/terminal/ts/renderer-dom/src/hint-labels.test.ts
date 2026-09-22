import { describe, expect, it } from "vitest";
import { computeLabelsForAlphabet, DEFAULT_HINT_ALPHABET } from "./hint-labels";

// wezterm/wezterm-gui/src/overlay/quickselect.rs mod alphabet_test
describe("computeLabelsForAlphabet", () => {
	it("simple_alphabet", () => {
		expect(computeLabelsForAlphabet("abcd", 3)).toEqual(["a", "b", "c"]);
	});
	it("more_matches_than_alphabet_can_represent", () => {
		expect(computeLabelsForAlphabet("asdfqwerzxcvjklmiuopghtybn", 792)).toHaveLength(676);
	});
	it("composed_single", () => {
		expect(computeLabelsForAlphabet("abcd", 6)).toEqual(["a", "b", "c", "da", "db", "dc"]);
	});
	it("composed_multiple", () => {
		expect(computeLabelsForAlphabet("abcd", 8)).toEqual(["a", "b", "ca", "cb", "da", "db", "dc", "dd"]);
	});
	it("composed_max", () => {
		expect(computeLabelsForAlphabet("ab", 5)).toEqual(["aa", "ab", "ba", "bb"]);
	});
	it("lowercases the alphabet", () => {
		expect(computeLabelsForAlphabet("AB", 4)).toEqual(["aa", "ab", "ba", "bb"]);
	});
	it("ships wezterm's default alphabet", () => {
		expect(DEFAULT_HINT_ALPHABET).toBe("asdfqwerzxcvjklmiuopghtybn");
	});
	it("returns nothing for no matches", () => {
		expect(computeLabelsForAlphabet("abc", 0)).toEqual([]);
	});
});
