function splitScheme(trimmed: string): [string, string] | null {
	const separator = trimmed.indexOf(":");
	if (separator < 0) return null;
	return [trimmed.slice(0, separator).toLowerCase(), trimmed.slice(separator + 1)];
}

function hasHttpSAuthority(remainder: string): boolean {
	if (!remainder.startsWith("//")) return false;
	const authority = remainder.slice(2).split(/[/?#]/)[0];
	return authority.length > 0 && !authority.includes("\\");
}

/** Strict preview-target allowlist: HTTP(S) with a non-empty authority only. */
export function isAllowedPreviewUrl(rawUrl: string): boolean {
	const trimmed = rawUrl.trim();
	if (!trimmed) return false;
	const parts = splitScheme(trimmed);
	if (!parts) return false;
	const [scheme, remainder] = parts;
	return (scheme === "http" || scheme === "https") && hasHttpSAuthority(remainder);
}
