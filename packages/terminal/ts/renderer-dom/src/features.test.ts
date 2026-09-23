import { describe, expect, it } from "vitest";
import { DEFAULT_FEATURES, parseFeatureList, resolveFeatures } from "./features";

describe("RendererFeatures", () => {
	it("defaults graphemes and widthCache on, attributes to warp and every other flag off", () => {
		expect(DEFAULT_FEATURES).toEqual({
			attributes: "warp",
			graphemes: true,
			cursorContrast: false,
			cursorHollowUnfocused: false,
			widthCache: true,
			boxDrawing: false,
		});
		expect(resolveFeatures()).toEqual(DEFAULT_FEATURES);
		expect(resolveFeatures({ graphemes: false })).toEqual({ ...DEFAULT_FEATURES, graphemes: false });
		expect(resolveFeatures({ attributes: "plain" })).toEqual({ ...DEFAULT_FEATURES, attributes: "plain" });
	});

	it("parses the harness list grammar", () => {
		expect(parseFeatureList("")).toEqual({});
		expect(parseFeatureList("attributes=warp,graphemes")).toEqual({ attributes: "warp", graphemes: true });
		expect(parseFeatureList("cursorContrast=false")).toEqual({ cursorContrast: false });
		expect(parseFeatureList("attributes=plain")).toEqual({ attributes: "plain" });
	});

	it("rejects a name it does not know and a bad attributes value", () => {
		expect(() => parseFeatureList("ligatures")).toThrow(/unknown feature/);
		expect(() => parseFeatureList("attributes=bold")).toThrow(/attributes/);
	});
});
