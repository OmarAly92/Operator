import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { fuzzyPolicyForToken, matchRanges, scoreMatch, scoreTextFields, type FuzzyPolicy, type MatchScore, type TextFieldsOptions } from "./text-match";

type FixtureOptions = { fuzzy?: FuzzyPolicy | "auto" | null; subsequence?: boolean };
type FixtureCase = { name: string; query: string; text: string; options: FixtureOptions; expect: MatchScore | null };
type TextFieldsCase = { name: string; query: string; fields: string[]; options: { typoTolerant?: boolean; subsequence?: boolean }; expect: MatchScore | null };
type RangeCase = { name: string; query: string; text: string; expect: { start: number; length: number }[] };

const fixture = JSON.parse(readFileSync(path.resolve(process.cwd(), "../testdata/search/text-match.json"), "utf8")) as {
  score: FixtureCase[];
  policy: { token: string; expect: FuzzyPolicy | null }[];
  textFields: TextFieldsCase[];
  ranges: RangeCase[];
};

function matchOptions(options: FixtureOptions, query: string): { fuzzy?: FuzzyPolicy | null; subsequence?: boolean } {
  return {
    fuzzy: options.fuzzy === "auto" ? fuzzyPolicyForToken(query) : options.fuzzy,
    subsequence: options.subsequence,
  };
}

describe("shared text match fixture", () => {
  for (const item of fixture.score) {
    it(item.name, () => {
      expect(scoreMatch(item.query, item.text, matchOptions(item.options, item.query))).toEqual(item.expect);
    });
  }

  for (const item of fixture.policy) {
    it(`policy: ${item.token}`, () => {
      expect(fuzzyPolicyForToken(item.token)).toEqual(item.expect);
    });
  }

  for (const item of fixture.textFields) {
    it(item.name, () => {
      expect(scoreTextFields(item.query, item.fields, item.options as TextFieldsOptions)).toEqual(item.expect);
    });
  }

  for (const item of fixture.ranges) {
    it(item.name, () => {
      const score = scoreMatch(item.query, item.text, { fuzzy: fuzzyPolicyForToken(item.query) });
      expect(score).not.toBeNull();
      expect(matchRanges(item.query, item.text, score!)).toEqual(item.expect);
    });
  }
});
