import { describe, expect, it } from "vitest";
import {
	APP_LOCALES,
	DEFAULT_LOCALE,
	DEFAULT_UI_SETTINGS,
	coerceLocale,
	coerceUiSettings,
} from "./ui-locale";

describe("shared UI locale schema", () => {
	it("supports English only", () => {
		expect(APP_LOCALES).toEqual(["en"]);
		expect(coerceLocale("en")).toBe("en");
		expect(coerceLocale("zh-CN")).toBe(DEFAULT_LOCALE);
		expect(coerceLocale("pt")).toBe(DEFAULT_LOCALE);
		expect(coerceLocale({ locale: "zh-CN" })).toBe(DEFAULT_LOCALE);
	});

	it("normalizes persisted settings through the shared locale validator", () => {
		expect(coerceUiSettings({ locale: "en" })).toEqual({ locale: "en" });
		expect(coerceUiSettings({ locale: "zh-CN" })).toEqual(DEFAULT_UI_SETTINGS);
		expect(coerceUiSettings({ locale: "pt" })).toEqual(DEFAULT_UI_SETTINGS);
		expect(coerceUiSettings(null)).toEqual(DEFAULT_UI_SETTINGS);
	});
});
