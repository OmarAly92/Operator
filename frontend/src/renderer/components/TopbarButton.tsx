import { ArrowDownUp } from "lucide-react";
import type { WorkspaceSummary } from "../types/workspace";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const topbarButtonVariants = cva(
	"inline-flex items-center transition-[filter,background,color,border-color] duration-fast disabled:opacity-60",
	{
		variants: {
			variant: {
				primary:
					"h-control-lg gap-1.5 rounded-lg border border-border-strong bg-transparent px-2.5 text-sm font-medium leading-none text-muted-foreground hover:bg-interactive-hover hover:text-foreground",
				accent:
					"h-control-lg gap-1.5 rounded-lg border border-transparent px-2.5 text-sm font-medium leading-none bg-secondary text-foreground hover:bg-interactive-active",
				icon: "grid size-control-lg place-items-center rounded-md text-muted-foreground hover:bg-interactive-hover hover:text-foreground",
				kill: "h-control-lg gap-1.5 rounded-md border border-transparent bg-transparent px-3.5 text-sm font-semibold leading-none text-error/80 hover:border-error/50 hover:bg-error/10 hover:text-error",
				killConfirm:
					"h-control-lg gap-1.5 rounded-md border border-error/40 bg-error/10 px-3 text-control font-semibold leading-none text-error hover:bg-error/16",
				killCancel:
					"h-control-lg rounded-md px-2.5 text-control font-semibold leading-none text-muted-foreground hover:text-foreground",
			},
		},
		defaultVariants: { variant: "primary" },
	},
);

export function TopbarButton({
	className,
	variant,
	type = "button",
	...props
}: React.ButtonHTMLAttributes<HTMLButtonElement> & VariantProps<typeof topbarButtonVariants>) {
	return <button className={cn(topbarButtonVariants({ variant }), className)} type={type} {...props} />;
}

export function TopbarKillError({ className, ...props }: React.HTMLAttributes<HTMLSpanElement>) {
	return <span className={cn("text-caption text-destructive", className)} role="alert" {...props} />;
}

export const topbarHeaderClass =
	"center-panel-titlebar flex h-toolbar shrink-0 items-center gap-3 border-b border-border pr-4 z-chrome";

export const topbarProjectLabelClass =
	"text-md font-semibold tracking-tight leading-none text-foreground whitespace-nowrap";

export function BoardDiff({ workspaces }: { workspaces: WorkspaceSummary[] }) {
	const knownDiffs = workspaces.flatMap((workspace) => workspace.diff ? [workspace.diff] : []);
	if (knownDiffs.length === 0) return null;
	const additions = knownDiffs.reduce((total, diff) => total + diff.additions, 0);
	const deletions = knownDiffs.reduce((total, diff) => total + diff.deletions, 0);
	return (
		<div className="inline-flex items-center gap-1.5 px-1 font-mono text-sm-md">
			<ArrowDownUp className="size-4 text-passive" aria-hidden="true" />
			<span className="text-success">+{additions}</span>
			<span className="text-error">−{deletions}</span>
		</div>
	);
}
