import { NgrokApiKeyCard } from "./NgrokApiKeyCard";
import { NgrokCredentialCard } from "./NgrokCredentialCard";
import { NgrokSessionCard } from "./NgrokSessionCard";
import type { MobileBridge } from "./useMobileBridge";
import type { Ngrok } from "./useNgrok";

interface NgrokSectionProps {
	bridge: MobileBridge;
	ngrok: Ngrok;
}

export function NgrokSection({ bridge, ngrok }: NgrokSectionProps) {
	return (
		<>
			<NgrokCredentialCard bridge={bridge} ngrok={ngrok} />
			<NgrokApiKeyCard bridge={bridge} ngrok={ngrok} />
			<NgrokSessionCard bridge={bridge} ngrok={ngrok} />
		</>
	);
}
