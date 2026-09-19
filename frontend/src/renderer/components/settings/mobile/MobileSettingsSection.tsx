import { useRef } from "react";
import { useTranslation } from "react-i18next";
import { SettingsSection } from "../SettingsSection";
import { MobileConnectionSection } from "./MobileConnectionSection";
import { MobilePublicAccessSection } from "./MobilePublicAccessSection";
import { NgrokSection } from "./NgrokSection";
import { useMobileBridge } from "./useMobileBridge";
import { useNgrok } from "./useNgrok";

export function MobileSettingsSection({ titleHidden }: { titleHidden?: boolean }) {
	const { t } = useTranslation();
	const bridge = useMobileBridge(true);
	const ngrok = useNgrok(true);
	const ngrokRef = useRef<HTMLDivElement>(null);
	return (
		<>
			<SettingsSection title={t("settings.mobile")} sectionId="mobile" titleHidden={titleHidden} grouped>
				<MobileConnectionSection bridge={bridge}>
					<MobilePublicAccessSection bridge={bridge} onManageNgrok={() => ngrokRef.current?.scrollIntoView({ behavior: "smooth", block: "start" })} />
				</MobileConnectionSection>
			</SettingsSection>
			<div ref={ngrokRef}>
				<SettingsSection title={t("mobile.ngrok.title")} sectionId="ngrok" grouped>
					<NgrokSection bridge={bridge} ngrok={ngrok} />
				</SettingsSection>
			</div>
		</>
	);
}
