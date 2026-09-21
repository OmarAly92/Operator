import { createInstance, type i18n } from "i18next";
import { initReactI18next } from "react-i18next";
import { DEFAULT_LOCALE } from "../../shared/ui-locale";
import { enMessages } from "./messages";

export type TranslationCatalogs = Record<typeof DEFAULT_LOCALE, Readonly<Record<string, string>>>;

export const appCatalogs: TranslationCatalogs = {
	en: enMessages,
};

/** Create an isolated, synchronously initialized instance for app startup and unit tests. */
export function createAppI18n(catalogs: TranslationCatalogs = appCatalogs): i18n {
	return initializeI18n(createInstance(), catalogs);
}

function initializeI18n(instance: i18n, catalogs: TranslationCatalogs): i18n {
	void instance.init({
		lng: DEFAULT_LOCALE,
		fallbackLng: DEFAULT_LOCALE,
		supportedLngs: [DEFAULT_LOCALE],
		load: "currentOnly",
		resources: { en: { translation: catalogs.en } },
		defaultNS: "translation",
		keySeparator: false,
		nsSeparator: false,
		returnNull: false,
		initAsync: false,
		interpolation: { escapeValue: false },
	});
	return instance;
}

export const appI18n = initializeI18n(createInstance().use(initReactI18next), appCatalogs);
