import { useTranslation } from "react-i18next";

import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
} from "../ui/dialog";
import { Button } from "../ui/button";

export const TUNNEL_CONFIRM_STORAGE_KEY = "opr.mobile.tunnelConfirmed";

export function tunnelAlreadyConfirmed(): boolean {
	try {
		return window.localStorage.getItem(TUNNEL_CONFIRM_STORAGE_KEY) === "1";
	} catch {
		return false;
	}
}

interface TunnelConfirmDialogProps {
	open: boolean;
	onOpenChange: (open: boolean) => void;
	onConfirm: () => void;
}

export function TunnelConfirmDialog({ open, onOpenChange, onConfirm }: TunnelConfirmDialogProps) {
	const { t } = useTranslation();

	const confirm = () => {
		try {
			window.localStorage.setItem(TUNNEL_CONFIRM_STORAGE_KEY, "1");
		} catch {
			void 0;
		}
		onConfirm();
		onOpenChange(false);
	};

	return (
		<Dialog open={open} onOpenChange={onOpenChange}>
			<DialogContent>
				<DialogHeader>
					<DialogTitle>{t("mobile.tunnel.confirmTitle")}</DialogTitle>
					<DialogDescription>{t("mobile.tunnel.confirmBody")}</DialogDescription>
				</DialogHeader>
				<DialogFooter>
					<Button type="button" variant="footer" onClick={() => onOpenChange(false)}>
						{t("blocks.cancel")}
					</Button>
					<Button type="button" onClick={confirm}>
						{t("mobile.tunnel.confirmAccept")}
					</Button>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}
