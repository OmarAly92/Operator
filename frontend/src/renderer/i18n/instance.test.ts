import { describe, expect, it } from "vitest";
import { coerceLocale, DEFAULT_LOCALE } from "./index";
import { appI18n, createAppI18n, type TranslationCatalogs } from "./instance";

describe("coerceLocale", () => {
	it("always resolves to English", () => {
		expect(coerceLocale("en")).toBe("en");
		expect(coerceLocale(undefined)).toBe(DEFAULT_LOCALE);
		expect(coerceLocale(null)).toBe("en");
		expect(coerceLocale("zh-CN")).toBe("en");
		expect(coerceLocale({ locale: "zh-CN" })).toBe("en");
	});
});

describe("app i18next instance", () => {
	it("ships exactly one locale", () => {
		expect(Object.keys(appI18n.options.resources ?? {})).toEqual(["en"]);
	});

	it("resolves a key through the English bundle", () => {
		expect(appI18n.t("zone.working")).not.toEqual("zone.working");
	});

	it("uses English by default", () => {
		expect(createAppI18n().t("settings.general")).toBe("General");
	});

	it("falls back to the key when a translation is missing", () => {
		const catalogs: TranslationCatalogs = { en: { "proof.onlyEn": "English only" } };
		const instance = createAppI18n(catalogs);
		expect(instance.t("proof.onlyEn", { defaultValue: "proof.onlyEn" })).toBe("English only");
		expect(instance.t("totally.missing", { defaultValue: "totally.missing" })).toBe("totally.missing");
	});

	it("uses standard interpolation and plural forms", () => {
		const catalogs: TranslationCatalogs = {
			en: {
				"proof.hello": "Hello, {{name}}!",
				"proof.item_one": "{{count}} item",
				"proof.item_other": "{{count}} items",
			},
		};
		const instance = createAppI18n(catalogs);
		expect(instance.t("proof.hello", { name: "Operator", defaultValue: "proof.hello" })).toBe("Hello, Operator!");
		expect(instance.t("proof.item", { count: 1, defaultValue: "proof.item" })).toBe("1 item");
		expect(instance.t("proof.item", { count: 2, defaultValue: "proof.item" })).toBe("2 items");
	});

	it("keeps unresolved placeholders visible", () => {
		const catalogs: TranslationCatalogs = { en: { "proof.x": "keep {{missing}}" } };
		expect(createAppI18n(catalogs).t("proof.x", { defaultValue: "proof.x" })).toBe("keep {{missing}}");
	});
});
