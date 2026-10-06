import { useTranslation } from "react-i18next";
import { cn } from "../../lib/utils";
import { useSplitDragStore } from "./split-drag-store";

export function SplitDragPreview() {
	const { t } = useTranslation();
	const drag = useSplitDragStore((state) => state.drag);
	const targeted = useSplitDragStore((state) => state.target !== null);
	if (!drag) return null;
	return (
		<div className="pointer-events-none relative">
			<div
				className={cn(
					"flex h-7 items-center gap-1.5 rounded-lg px-2.5 text-control text-foreground transition-opacity duration-[120ms]",
					targeted ? "opacity-0" : "opacity-60",
				)}
				data-testid="split-drag-row"
			>
				<span aria-hidden="true" className="size-1.5 shrink-0 rounded-full bg-passive" />
				<span className="max-w-56 truncate">{drag.label}</span>
			</div>
			<div
				className={cn(
					"absolute left-0 top-0 inline-flex h-7 items-center whitespace-nowrap rounded-lg border border-border bg-overlay px-2.5 text-control text-foreground shadow-md transition-opacity duration-[120ms]",
					targeted ? "opacity-100" : "opacity-0",
				)}
				data-testid="split-drag-chip"
			>
				{t("split.openInSplitView")}
			</div>
		</div>
	);
}
