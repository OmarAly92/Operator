import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
	define: {
		"import.meta.env.TERMINAL_SMOKE_REPORT_URL": JSON.stringify(
			process.env.TERMINAL_SMOKE_REPORT_URL ?? "",
		),
	},
	plugins: [react()],
	server: {
		host: "127.0.0.1",
		port: 0,
		strictPort: false,
	},
	build: {
		target: "es2022",
		outDir: "dist",
		emptyOutDir: true,
		sourcemap: true,
	},
});
