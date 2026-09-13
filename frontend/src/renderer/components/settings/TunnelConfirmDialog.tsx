import { useTranslation } from "react-i18next";

import { rememberTunnelConfirmed } from "../../lib/tunnel-confirm";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
} from "../ui/dialog";
import { Button } from "../ui/button";

interface TunnelConfirmDialogProps {
	open: boolean;
	onOpenChange: (open: boolean) => void;
	onConfirm: () => void;
}

export function TunnelConfirmDialog({ open, onOpenChange, onConfirm }: TunnelConfirmDialogProps) {
	const { t } = useTranslation();

	const confirm = () => {
		rememberTunnelConfirmed();
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
