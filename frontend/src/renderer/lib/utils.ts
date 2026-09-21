import { clsx, type ClassValue } from "clsx";
import { extendTailwindMerge } from "tailwind-merge";

// The token-named font sizes declared in styles.css `@theme` (text-control,
// text-2xs, …). Without this tailwind-merge reads `text-control` as a text
// colour and drops it when a `text-<colour>` class follows in the same cn().
const twMerge = extendTailwindMerge({
	extend: {
		classGroups: {
			"font-size": [
				"text-micro",
				"text-2xs",
				"text-caption",
				"text-sm-md",
				"text-md-sm",
				"text-control",
				"text-brand",
				"text-subtitle",
				"text-heading-sm",
				"text-heading",
				"text-heading-lg",
			],
		},
	},
});

export function cn(...inputs: ClassValue[]) {
	return twMerge(clsx(inputs));
}
