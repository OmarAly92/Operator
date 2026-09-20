import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { defineConfig, type Plugin } from "vite";

const root = fileURLToPath(new URL(".", import.meta.url));

function serveFixtureRecordings(): Plugin {
	return {
		name: "serve-fixture-recordings",
		configureServer(server) {
			server.middlewares.use(async (req, res, next) => {
				if (!req.url || !req.url.endsWith("/recording")) return next();
				const relative = req.url.split("?")[0]!.replace(/^\/+/, "");
				const file = path.join(root, relative);
				try {
					const data = await readFile(file);
					res.setHeader("Content-Type", "application/octet-stream");
					res.end(data);
				} catch {
					next();
				}
			});
		},
	};
}

export default defineConfig({
	root,
	plugins: [serveFixtureRecordings()],
	server: {
		host: "127.0.0.1",
		port: 0,
		strictPort: false,
	},
	build: {
		target: "es2022",
		outDir: "dist",
		emptyOutDir: true,
		chunkSizeWarningLimit: 550,
	},
});
