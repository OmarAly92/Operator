import { useMutation } from "@tanstack/react-query";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Eye, EyeOff, Loader2 } from "lucide-react";

import { apiClient, apiErrorMessage } from "../../lib/api-client";
import { operatorBridge } from "../../lib/bridge";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
} from "../ui/dialog";
import { Button } from "../ui/button";
import { Input } from "../ui/input";

export const NGROK_AUTHTOKEN_URL = "https://dashboard.ngrok.com/get-started/your-authtoken";

interface NgrokAuthtokenDialogProps {
	open: boolean;
	onOpenChange: (open: boolean) => void;
	onSaved: () => void;
}

export function NgrokAuthtokenDialog({ open, onOpenChange, onSaved }: NgrokAuthtokenDialogProps) {
	const { t } = useTranslation();
	const [token, setToken] = useState("");
	const [revealed, setRevealed] = useState(false);

	const save = useMutation({
		mutationFn: async (value: string) => {
			const { data, error } = await apiClient.POST("/api/v1/mobile/tunnel/authtoken", {
				body: { token: value },
			});
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSuccess: () => {
			setToken("");
			setRevealed(false);
			onSaved();
			onOpenChange(false);
		},
	});

	const submit = () => {
		const trimmed = token.trim();
		if (trimmed === "" || save.isPending) return;
		save.mutate(trimmed);
	};

	const dismiss = () => {
		setToken("");
		setRevealed(false);
		save.reset();
		onOpenChange(false);
	};

	return (
		<Dialog open={open} onOpenChange={onOpenChange}>
			<DialogContent>
				<DialogHeader>
					<DialogTitle>{t("mobile.tunnel.tokenTitle")}</DialogTitle>
					<DialogDescription>{t("mobile.tunnel.tokenBody")}</DialogDescription>
				</DialogHeader>

				<Button
					type="button"
					variant="footer"
					onClick={() => void operatorBridge.app.openExternal(NGROK_AUTHTOKEN_URL)}
				>
					{t("mobile.tunnel.tokenGet")}
				</Button>

				<label className="mt-2 flex flex-col gap-1 text-caption text-settings-muted" htmlFor="ngrok-authtoken">
					{t("mobile.tunnel.tokenLabel")}
					<div className="flex items-center gap-2">
						<Input
							id="ngrok-authtoken"
							type={revealed ? "text" : "password"}
							value={token}
							onChange={(event) => setToken(event.target.value)}
							autoComplete="off"
							className="flex-1"
						/>
						<button
							type="button"
							aria-label={t("mobile.tunnel.tokenLabel")}
							onClick={() => setRevealed((value) => !value)}
							className="inline-flex size-6 shrink-0 items-center justify-center text-settings-muted hover:text-settings-label"
						>
							{revealed ? <EyeOff className="size-4" aria-hidden="true" /> : <Eye className="size-4" aria-hidden="true" />}
						</button>
					</div>
				</label>

				{save.error instanceof Error && <p className="text-xs text-error">{save.error.message}</p>}

				<DialogFooter>
					<Button type="button" variant="footer" onClick={dismiss}>
						{t("mobile.tunnel.tokenDismiss")}
					</Button>
					<Button type="button" onClick={submit} disabled={save.isPending || token.trim() === ""}>
						{save.isPending && <Loader2 className="mr-2 size-4 animate-spin" aria-hidden="true" />}
						{t("mobile.tunnel.tokenSave")}
					</Button>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}
