import { Check, Loader2, X } from "lucide-react";
import { useTranslation } from "react-i18next";

import { SettingsRow } from "../SettingsRow";
import { Button } from "../../ui/button";
import { NgrokLogPanel } from "./NgrokLogPanel";
import type { Ngrok } from "./useNgrok";

interface NgrokDiagnosticsCardProps {
	ngrok: Ngrok;
}

export function NgrokDiagnosticsCard({ ngrok }: NgrokDiagnosticsCardProps) {
	const { t } = useTranslation();
	const diagnosis = ngrok.diagnose.data;
	const ok = diagnosis ? diagnosis.checks.every((check) => check.ok) : true;

	return (
		<>
			<SettingsRow label={t("mobile.ngrok.diagnostics")}>
				<div className="flex min-w-0 flex-1 flex-col items-end gap-2">
					<Button
						type="button"
						variant="footer"
						size="sm"
						onClick={() => ngrok.diagnose.mutate()}
						disabled={ngrok.diagnose.isPending}
					>
						{ngrok.diagnose.isPending && <Loader2 className="mr-2 size-4 animate-spin" aria-hidden="true" />}
						{t("mobile.ngrok.runDiagnostics")}
					</Button>
					{diagnosis && (
						<>
							<p className={ok ? "text-settings-muted" : "text-warning"}>{diagnosis.summary}</p>
							<ul className="flex w-full flex-col gap-1">
								{diagnosis.checks.map((check) => (
									<li key={check.name} data-ok={String(check.ok)} className="flex items-start gap-2">
										{check.ok ? (
											<Check className="mt-0.5 size-4 shrink-0 text-working" aria-hidden="true" />
										) : (
											<X className="mt-0.5 size-4 shrink-0 text-error" aria-hidden="true" />
										)}
										<div className="flex min-w-0 flex-col">
											<span className="text-settings-label">{check.name}</span>
											{check.detail !== diagnosis.summary && (
												<span className="text-caption text-settings-muted">{check.detail}</span>
											)}
										</div>
									</li>
								))}
							</ul>
						</>
					)}
				</div>
			</SettingsRow>
			<NgrokLogPanel lines={ngrok.status?.logs ?? []} />
		</>
	);
}
