import { ChevronDown, ChevronUp, Filter, X } from "lucide-react";
import type { KeyboardEvent } from "react";
import { useTranslation } from "react-i18next";
import { Button } from "../ui/button";
import { Input } from "../ui/input";

export function BlockFindBar({
	query,
	onQueryChange,
	matchCount,
	activeIndex,
	onPrevious,
	onNext,
	filtering,
	onToggleFilter,
	onClose,
}: {
	query: string;
	onQueryChange: (query: string) => void;
	matchCount: number;
	activeIndex: number;
	onPrevious: () => void;
	onNext: () => void;
	filtering: boolean;
	onToggleFilter: () => void;
	onClose: () => void;
}) {
	const { t } = useTranslation();
	const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
		if (event.key === "Escape") {
			event.preventDefault();
			onClose();
			return;
		}
		if (event.key !== "Enter") return;
		event.preventDefault();
		if (event.shiftKey) onPrevious();
		else onNext();
	};

	return (
		<div aria-label={t("blocks.find.open")} className="flex items-center gap-1 border-border border-b px-3 py-2" onKeyDown={onKeyDown} role="search">
			<Input
				aria-label={t("blocks.find.open")}
				autoFocus
				onChange={(event) => onQueryChange(event.target.value)}
				placeholder={t("blocks.find.placeholder")}
				value={query}
			/>
			<span className="shrink-0 text-muted-foreground text-xs">
				{matchCount === 0 ? t("blocks.find.noMatches") : t("blocks.find.counter", { index: activeIndex + 1, total: matchCount })}
			</span>
			<Button aria-label={t("blocks.find.previous")} disabled={matchCount === 0} onClick={onPrevious} size="icon" variant="ghost">
				<ChevronUp className="size-4" />
			</Button>
			<Button aria-label={t("blocks.find.next")} disabled={matchCount === 0} onClick={onNext} size="icon" variant="ghost">
				<ChevronDown className="size-4" />
			</Button>
			<Button aria-label={t("blocks.find.filter")} aria-pressed={filtering} onClick={onToggleFilter} size="icon" variant="ghost">
				<Filter className="size-4" />
			</Button>
			<Button aria-label={t("blocks.find.close")} onClick={onClose} size="icon" variant="ghost">
				<X className="size-4" />
			</Button>
		</div>
	);
}
