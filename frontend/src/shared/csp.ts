// CSP for the built renderer. The daemon is loopback-only, so network access is
// pinned to 127.0.0.1 (REST + SSE over http, terminal mux over ws).
//
// script-src carries 'wasm-unsafe-eval' because the terminal core is a WASM
// module: WebKit refuses `WebAssembly.instantiate` under a bare 'self' with
// "Refused to create a WebAssembly object", which left every terminal pane
// blank in packaged builds while dev (no CSP) rendered fine. 'wasm-unsafe-eval'
// permits WASM compilation only -- it does not re-enable eval() for scripts,
// which is why the broader 'unsafe-eval' stays out.
export function buildContentSecurityPolicy(posthogOrigins: readonly string[]): string {
	return [
		"default-src 'self'",
		"script-src 'self' 'wasm-unsafe-eval'",
		"style-src 'self' 'unsafe-inline'",
		"img-src 'self' data: http://127.0.0.1:*",
		"font-src 'self' data:",
		["connect-src", "'self'", "http://127.0.0.1:*", "ws://127.0.0.1:*", ...posthogOrigins].filter(Boolean).join(" "),
		"object-src 'none'",
		"base-uri 'self'",
		"frame-src 'none'",
	].join("; ");
}
