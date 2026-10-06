import type { TFunction } from "i18next";
import { ChevronDown, GitBranch, Search } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import type { ProjectBranch } from "../hooks/useProjectBranches";
import { useSuppressStrayFocusRing } from "../hooks/useSuppressStrayFocusRing";
import { cn } from "../lib/utils";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "./ui/dropdown-menu";

const BRANCH_SEARCH_THRESHOLD = 10;

type TaskBranchPickerProps = {
	id: string;
	worktree: boolean;
	value: string;
	current: string;
	branches: ProjectBranch[];
	loading: boolean;
	failed: boolean;
	onPick: (pick: { worktree: boolean; branch: string }) => void;
};

function busyBranchReason(branch: ProjectBranch, t: TFunction) {
	if (!branch.checkedOutAt || branch.isMainCheckout) return undefined;
	const folder = branch.checkedOutAt.replace(/[/\\]+$/, "").split(/[/\\]/).pop() ?? branch.checkedOutAt;
	return t("newTask.branchInUseBy", { folder });
}

export function TaskBranchPicker({ id, worktree, value, current, branches, loading, failed, onPick }: TaskBranchPickerProps) {
	const { t } = useTranslation();
	const [search, setSearch] = useState("");
	const [menuOpen, setMenuOpen] = useState(false);
	const onCloseAutoFocus = useSuppressStrayFocusRing(menuOpen);

	const triggerClass =
		"composer-chip max-w-56 justify-between rounded-md! text-caption text-muted-foreground hover:text-foreground";

	const query = search.trim().toLocaleLowerCase();
	const visible = query ? branches.filter((branch) => branch.name.toLocaleLowerCase().includes(query)) : branches;
	const label = worktree ? value || t("newTask.newBranch") : current || t("newTask.detachedHead");

	return (
		<DropdownMenu
			onOpenChange={(open) => {
				setMenuOpen(open);
				if (!open) setSearch("");
			}}
		>
			<DropdownMenuTrigger asChild>
				<button type="button" id={id} aria-label={t("newTask.branch")} className={cn("group/branch-trigger", triggerClass)}>
					<GitBranch className="size-icon-sm shrink-0" aria-hidden="true" />
					<span className="min-w-0 truncate">{label}</span>
					<ChevronDown
						className="size-icon-sm shrink-0 opacity-70 transition-transform duration-300 ease-out group-data-[state=open]/branch-trigger:rotate-180"
						aria-hidden="true"
					/>
				</button>
			</DropdownMenuTrigger>
			<DropdownMenuContent
				align="start"
				onCloseAutoFocus={onCloseAutoFocus}
				className="settings-menu-surface max-h-select-menu-max! w-[min(22rem,calc(100vw-2rem))] overflow-hidden! rounded-(--radius-settings-panel) border-settings-menu bg-settings-menu"
			>
				{branches.length > BRANCH_SEARCH_THRESHOLD && (
					<div className="relative shrink-0 p-1" onKeyDown={(event) => event.stopPropagation()}>
						<Search
							className="pointer-events-none absolute left-3.5 top-1/2 size-icon-sm -translate-y-1/2 text-settings-muted"
							aria-hidden="true"
						/>
						<input
							type="search"
							aria-label={t("newTask.searchBranches")}
							value={search}
							onChange={(event) => setSearch(event.target.value)}
							placeholder={t("newTask.searchBranches")}
							className="menu-search-input pl-8!"
						/>
					</div>
				)}
				<div className="model-menu-scroll min-h-0 overflow-y-auto overscroll-contain">
					{query === "" && (
						<DropdownMenuItem
							onSelect={() => onPick({ worktree: true, branch: "" })}
							className={branchItemClass(worktree && value === "")}
						>
							{t("newTask.newBranch")}
						</DropdownMenuItem>
					)}
					{visible.map((branch) => {
						const reason = busyBranchReason(branch, t);
						const selected = branch.isMainCheckout ? !worktree : worktree && branch.name === value;
						return (
							<DropdownMenuItem
								key={branch.name}
								disabled={reason !== undefined}
								onSelect={() =>
									onPick(branch.isMainCheckout ? { worktree: false, branch: "" } : { worktree: true, branch: branch.name })
								}
								className={branchItemClass(selected)}
							>
								<div className="min-w-0 flex-1">
									<p className="truncate text-settings-label">{branch.name}</p>
									{branch.isMainCheckout && (
										<p className="text-xs whitespace-normal text-settings-muted">{t("newTask.branchInProjectFolder")}</p>
									)}
									{reason && <p className="text-xs whitespace-normal text-settings-muted">{reason}</p>}
								</div>
							</DropdownMenuItem>
						);
					})}
					{loading && <p className="px-2 py-1.5 text-xs text-settings-muted">{t("newTask.loadingBranches")}</p>}
					{failed && <p className="px-2 py-1.5 text-xs text-settings-muted">{t("newTask.branchesFailed")}</p>}
					{query !== "" && visible.length === 0 && (
						<p className="px-2 py-1.5 text-xs text-settings-muted">{t("newTask.noBranchMatches")}</p>
					)}
				</div>
			</DropdownMenuContent>
		</DropdownMenu>
	);
}

function branchItemClass(selected: boolean): string {
	return cn(
		"settings-menu-item min-w-0 cursor-default outline-none",
		"focus:bg-settings-menu-selected focus:text-settings-title",
		"data-highlighted:bg-settings-menu-selected data-highlighted:text-settings-title",
		"data-disabled:opacity-60",
		selected && "border-settings-menu bg-settings-menu-selected text-settings-title",
	);
}
