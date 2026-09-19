import { useTranslation } from "react-i18next";
import { X } from "lucide-react";

import { cn } from "../lib/utils";
import { useUiStore } from "../stores/ui-store";
import { useMobileBridge } from "./settings/mobile/useMobileBridge";
import { MobileConnectionSection } from "./settings/mobile/MobileConnectionSection";
import { MobilePublicAccessSection } from "./settings/mobile/MobilePublicAccessSection";
import {
	Dialog,
	DialogClose,
	DialogContent,
	DialogDescription,
	DialogHeader,
	DialogTitle,
	settingsDialogBodyClass,
	settingsDialogContentClass,
	settingsDialogHeaderClass,
} from "./ui/dialog";

interface ConnectMobileModalProps {
	open: boolean;
	onOpenChange: (open: boolean) => void;
}

export function ConnectMobileModal({ open, onOpenChange }: ConnectMobileModalProps) {
	const { t } = useTranslation();
	const bridge = useMobileBridge(open);
	const openMobileSettings = useUiStore((s) => s.openMobileSettings);
	return (
		<Dialog open={open} onOpenChange={onOpenChange}>
			<DialogContent
				showCloseButton={false}
				className={cn(settingsDialogContentClass, "w-[min(var(--size-settings-mobile-dialog),calc(100vw-var(--space-8)))]")}
			>
				<DialogClose asChild>
					<button
						type="button"
						className="settings-dialog-close-button settings-close-button"
						aria-label={t("mobile.close")}
					>
						<X className="size-5" aria-hidden="true" />
					</button>
				</DialogClose>
				<DialogHeader className={cn(settingsDialogHeaderClass, "items-start text-left")}>
					<DialogTitle className="settings-dialog-title text-left">{t("mobile.title")}</DialogTitle>
					<DialogDescription className="max-w-(--size-settings-mobile-desc) text-left text-control font-normal leading-4 text-settings-muted">
						{t("mobile.description")}
					</DialogDescription>
				</DialogHeader>
				<div className={cn(settingsDialogBodyClass, "max-h-[80vh] gap-0 pt-6 scrollbar-none")}>
					<MobileConnectionSection bridge={bridge}>
						<MobilePublicAccessSection
							bridge={bridge}
							onManageNgrok={() => {
								onOpenChange(false);
								openMobileSettings();
							}}
						/>
					</MobileConnectionSection>
				</div>
			</DialogContent>
		</Dialog>
	);
}
