import { createContext, useContext, type ReactNode } from "react";
import type { AppSkin } from "./app-skin";
import { darkSkin } from "./skins/dark";

const SkinContext = createContext<AppSkin>(darkSkin);

export function SkinProvider({ skin, children }: { skin: AppSkin; children: ReactNode }) {
	return <SkinContext.Provider value={skin}>{children}</SkinContext.Provider>;
}

export function useSkin(): AppSkin {
	return useContext(SkinContext);
}
