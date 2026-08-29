import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
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
