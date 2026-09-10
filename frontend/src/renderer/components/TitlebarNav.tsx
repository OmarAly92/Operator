import type { ReactNode, PointerEventHandler } from "react";
import { LayoutGrid, PanelLeft, Search, Wrench } from "lucide-react";
import { useTranslation } from "react-i18next";
import { isMacPlatform, isWindowsPlatform, windowDragRegion } from "../lib/platform";
import { useUiStore } from "../stores/ui-store";
import { cn } from "../lib/utils";

export function TitlebarNav({
	isFullScreen = false,
	onSidebarPreviewEnter,
	onGoHome,
	notifications,
	searchEnabled = true,
}: {
	isFullScreen?: boolean;
	onSidebarPreviewEnter?: PointerEventHandler<HTMLButtonElement>;
	onGoHome: () => void;
	notifications?: ReactNode;
	searchEnabled?: boolean;
}) {
	const { t } = useTranslation();
	const isSidebarOpen = useUiStore((state) => state.isSidebarOpen);
	const toggleSidebar = useUiStore((state) => state.toggleSidebar);
	const openGlobalSettings = useUiStore((state) => state.openGlobalSettings);
	const setCommandPaletteOpen = useUiStore((state) => state.setCommandPaletteOpen);
	return (
		<header
			className={cn("desktop-titlebar", isMacPlatform() && !isFullScreen && "desktop-titlebar--mac")}
			data-slot="titlebar-nav"
			data-tauri-drag-region={windowDragRegion()}
		>
			<div className="desktop-titlebar__navigation">
				{!isWindowsPlatform() && (
					<button type="button" className="desktop-titlebar__icon" aria-label={isSidebarOpen ? t("shell.collapseSidebar") : t("shell.expandSidebar")} aria-pressed={isSidebarOpen} onClick={toggleSidebar} onPointerEnter={onSidebarPreviewEnter}>
						<PanelLeft aria-hidden="true" />
					</button>
				)}
				<button type="button" className="desktop-titlebar__icon" aria-label={t("shell.settings")} onClick={openGlobalSettings}>
					<Wrench aria-hidden="true" />
				</button>
				<button type="button" className="desktop-titlebar__icon" aria-label={t("shell.board")} onClick={onGoHome}>
					<LayoutGrid aria-hidden="true" />
				</button>
			</div>
			{searchEnabled && (
				<button type="button" className="desktop-titlebar__search" aria-label={t("shell.search")} onClick={() => setCommandPaletteOpen(true)}>
					<Search aria-hidden="true" />
					<span>{t("shell.globalSearchPlaceholder")}</span>
				</button>
			)}
			<div className="desktop-titlebar__account">
				{notifications}
				<button type="button" className="desktop-titlebar__avatar" aria-label={t("shell.accountSettings")} onClick={openGlobalSettings}>O</button>
			</div>
		</header>
	);
}
