import { useMutation } from "@tanstack/react-query";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Loader2 } from "lucide-react";

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

export const NGROK_API_KEYS_URL = "https://dashboard.ngrok.com/api-keys";

interface NgrokApiKeyDialogProps {
	open: boolean;
	onOpenChange: (open: boolean) => void;
	onSave: (key: string) => Promise<unknown>;
}

export function NgrokApiKeyDialog({ open, onOpenChange, onSave }: NgrokApiKeyDialogProps) {
	const { t } = useTranslation();
	const [key, setKey] = useState("");

	const save = useMutation({
		mutationFn: (value: string) => onSave(value),
		onSuccess: () => {
			setKey("");
			onOpenChange(false);
		},
	});

	const submit = () => {
		const trimmed = key.trim();
		if (trimmed === "" || save.isPending) return;
		save.mutate(trimmed);
	};

	const dismiss = () => {
		setKey("");
		save.reset();
		onOpenChange(false);
	};

	return (
		<Dialog open={open} onOpenChange={onOpenChange}>
			<DialogContent>
				<DialogHeader>
					<DialogTitle>{t("mobile.ngrok.apiKeyTitle")}</DialogTitle>
					<DialogDescription>{t("mobile.ngrok.apiKeyBody")}</DialogDescription>
				</DialogHeader>

				<Button
					type="button"
					variant="footer"
					onClick={() => void operatorBridge.app.openExternal(NGROK_API_KEYS_URL)}
				>
					{t("mobile.ngrok.openApiKeys")}
				</Button>

				<label className="mt-2 flex flex-col gap-1 text-caption text-settings-muted" htmlFor="ngrok-api-key">
					{t("mobile.ngrok.apiKeyLabel")}
					<Input
						id="ngrok-api-key"
						type="password"
						value={key}
						onChange={(event) => setKey(event.target.value)}
						autoComplete="off"
					/>
				</label>

				{save.error instanceof Error && <p className="text-xs text-error">{save.error.message}</p>}

				<DialogFooter>
					<Button type="button" variant="footer" onClick={dismiss}>
						{t("blocks.cancel")}
					</Button>
					<Button type="button" onClick={submit} disabled={save.isPending || key.trim() === ""}>
						{save.isPending && <Loader2 className="mr-2 size-4 animate-spin" aria-hidden="true" />}
						{t("mobile.ngrok.save")}
					</Button>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}
