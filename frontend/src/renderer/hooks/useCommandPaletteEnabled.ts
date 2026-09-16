import { useQuery } from "@tanstack/react-query";
import { operatorBridge } from "../lib/bridge";

export function isCommandPaletteEnabled(version?: string, isDev: boolean = import.meta.env.DEV): boolean {
	return isDev || Boolean(version?.trim());
}

export function useAppVersion(): string | undefined {
	const { data } = useQuery({
		queryKey: ["app-version"],
		queryFn: () => operatorBridge.app.getVersion(),
		staleTime: Infinity,
	});
	return typeof data === "string" ? data : undefined;
}

export function useCommandPaletteEnabled(): boolean {
	return isCommandPaletteEnabled(useAppVersion());
}
