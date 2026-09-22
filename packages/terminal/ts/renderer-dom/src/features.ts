export type RendererFeatures = Readonly<{
	attributes: "plain" | "warp";
	graphemes: boolean;
	cursorContrast: boolean;
	cursorHollowUnfocused: boolean;
	widthCache: boolean;
	boxDrawing: boolean;
}>;

export const DEFAULT_FEATURES: RendererFeatures = {
	attributes: "plain",
	graphemes: false,
	cursorContrast: false,
	cursorHollowUnfocused: false,
	widthCache: false,
	boxDrawing: false,
};

const BOOLEAN_FEATURES = ["graphemes", "cursorContrast", "cursorHollowUnfocused", "widthCache", "boxDrawing"] as const;

export function resolveFeatures(partial?: Partial<RendererFeatures>): RendererFeatures {
	return { ...DEFAULT_FEATURES, ...partial };
}

export function parseFeatureList(text: string): Partial<RendererFeatures> {
	const out: Record<string, string | boolean> = {};
	for (const item of text.split(",")) {
		const entry = item.trim();
		if (entry === "") continue;
		const [name, value] = entry.split("=", 2) as [string, string | undefined];
		if (name === "attributes") {
			if (value !== "plain" && value !== "warp") throw new Error(`attributes must be plain or warp, got ${String(value)}`);
			out.attributes = value;
			continue;
		}
		if (!(BOOLEAN_FEATURES as readonly string[]).includes(name)) throw new Error(`unknown feature ${name}`);
		out[name] = value === undefined ? true : value === "true";
	}
	return out as Partial<RendererFeatures>;
}

export function sameFeatures(a: RendererFeatures, b: RendererFeatures): boolean {
	return a.attributes === b.attributes && BOOLEAN_FEATURES.every((name) => a[name] === b[name]);
}
