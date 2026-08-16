import { createContext, useContext, type ReactNode } from "react";
import type { AppSkin } from "./app-skin";
import { darkSkin } from "./skins/dark";
import { skinFor } from "./skins";
import { useUiStore } from "../stores/ui-store";

const SkinContext = createContext<AppSkin>(darkSkin);

export function SkinProvider({ children }: { children: ReactNode }) {
	const themeStyle = useUiStore((state) => state.themeStyle);
	const resolvedTheme = useUiStore((state) => state.resolvedTheme);
	const skin = skinFor(themeStyle, resolvedTheme);
	return <SkinContext.Provider value={skin}>{children}</SkinContext.Provider>;
}

export function useSkin(): AppSkin {
	return useContext(SkinContext);
}
