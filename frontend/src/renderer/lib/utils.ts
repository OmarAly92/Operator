import { clsx, type ClassValue } from "clsx";
import { extendTailwindMerge } from "tailwind-merge";

// The token-named sizes declared in styles.css `@theme`. Without these
// tailwind-merge reads `text-control` as a text colour and drops it when a
// `text-<colour>` follows in the same cn(), and cannot tell that `h-7`
// should replace `h-control-form`.
const spacingTokens = [
	"board-empty",
	"branch-chip",
	"browser-min",
	"browser-url",
	"content-max",
	"control-board",
	"control-board-sm",
	"control-form",
	"control-lg",
	"control-md",
	"control-sm",
	"control-xl",
	"control-xs",
	"daemon-failure-details-max",
	"dot-sm",
	"empty-offset-y",
	"flex-min",
	"font-size-label",
	"inspector-min",
	"inspector-tabs",
	"kv-label",
	"notification-icon",
	"notification-max-height",
	"notification-width",
	"pr-col-number",
	"pr-col-state",
	"pr-table-actions",
	"preview-content",
	"preview-max",
	"row-md",
	"select-menu-max",
	"session-topbar",
	"shell-tab-connected",
	"shell-tab-max",
	"shell-tab-min",
	"sidebar-project-actions",
	"table-head",
	"textarea-min",
	"titlebar-cluster-left",
	"titlebar-cluster-left-fullscreen",
	"titlebar-content-offset",
	"toolbar",
	"traffic-light-clearance",
	"traffic-light-clearance-fullscreen",
	"window-titlebar",
];

const twMerge = extendTailwindMerge({
	extend: {
		theme: {
			spacing: spacingTokens,
		},
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
