import { fileURLToPath, URL } from "node:url";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "vite";

export default defineConfig({
	root: fileURLToPath(new URL("./perf/terminal", import.meta.url)),
	resolve: {
		alias: {
			"@": fileURLToPath(new URL("./src/renderer", import.meta.url)),
		},
	},
	server: {
		host: "127.0.0.1",
		strictPort: true,
	},
	plugins: [react(), tailwindcss()],
	build: {
		emptyOutDir: true,
		outDir: fileURLToPath(new URL("./dist-terminal-perf", import.meta.url)),
	},
});
