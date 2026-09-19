import { useTranslation } from "react-i18next";
import { SettingsSection } from "../SettingsSection";

export function MobileSettingsSection({ titleHidden }: { titleHidden?: boolean }) {
	const { t } = useTranslation();
	return (
		<SettingsSection title={t("settings.mobile")} sectionId="mobile" titleHidden={titleHidden} grouped>
			<></>
		</SettingsSection>
	);
}
