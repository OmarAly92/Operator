import { PanelLeft } from "lucide-react";
import { useTranslation } from "react-i18next";
import { isLinuxPlatform, isMacPlatform } from "../lib/platform";
import { useUiStore } from "../stores/ui-store";

const isMac = isMacPlatform();
const isLinux = isLinuxPlatform();

// Sidebar chrome cluster. It stays fixed while the sidebar expands, collapses,
// or appears as a hover preview. macOS pins it beside the traffic lights; Linux
// has no traffic lights, so it sits at the sidebar's top-left. (Windows keeps
// this control in its own titlebar.)
export function TitlebarNav({
	hasSessionTopbar = false,
	isFullScreen = false,
	onSidebarPreviewEnter,
}: {
	hasSessionTopbar?: boolean;
	isFullScreen?: boolean;
	onSidebarPreviewEnter?: React.PointerEventHandler<HTMLButtonElement>;
}) {
	const { t } = useTranslation();
	const { isSidebarOpen, toggleSidebar } = useUiStore();

	if (!isMac && !isLinux) return null;

	// macOS: pinned beside the traffic lights. Native dots sit at y: 14 with a
	// 12px hit target, so their centerline is the 40px clearance band's own
	// centre and the items-centered band needs no offset. Linux: no traffic
	// lights, so it sits at the sidebar's top-left within the reserved titlebar
	// band.
	const leftClass = !isMac
		? "left-0"
		: isFullScreen
			? "left-titlebar-cluster-left-fullscreen"
			: "left-titlebar-cluster-left";
	// Linux: match the framed board titlebar's y (mac inset 2px + surface border
	// 1px) so the cluster shares its centerline with the project title.
	const topClass = !isMac
		? "top-0.75"
		: isFullScreen && hasSessionTopbar && !isSidebarOpen
			? "top-1.5"
			: "top-0";
	const heightClass = isMac && isFullScreen ? "h-traffic-light-clearance-fullscreen" : "h-traffic-light-clearance";

	return (
		<div
			className={`fixed ${topClass} ${leftClass} z-titlebar flex ${heightClass} items-center gap-1`}
			data-slot="titlebar-nav"
		>
			<TitlebarButton
				label={isSidebarOpen ? t("shell.collapseSidebar") : t("shell.expandSidebar")}
				onClick={toggleSidebar}
				onPointerEnter={onSidebarPreviewEnter}
				title={isSidebarOpen ? t("titlebar.collapseSidebarShortcut") : t("titlebar.expandSidebarShortcut")}
			>
				<PanelLeft className="size-icon-lg" aria-hidden="true" />
			</TitlebarButton>
		</div>
	);
}

function TitlebarButton({
	label,
	title,
	disabled,
	tabIndex,
	onClick,
	onPointerEnter,
	children,
}: {
	label: string;
	title: string;
	disabled?: boolean;
	tabIndex?: number;
	onClick: () => void;
	onPointerEnter?: React.PointerEventHandler<HTMLButtonElement>;
	children: React.ReactNode;
}) {
	return (
		<button
			aria-label={label}
			aria-disabled={disabled || undefined}
			className="grid size-control-md place-items-center rounded-md text-passive transition-colors hover:bg-interactive-hover hover:text-muted-foreground disabled:cursor-not-allowed disabled:opacity-55 disabled:hover:bg-transparent disabled:hover:text-passive"
			disabled={disabled}
			onClick={onClick}
			onPointerEnter={onPointerEnter}
			tabIndex={tabIndex}
			title={title}
			type="button"
		>
			{children}
		</button>
	);
}
