import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), "probes", "act-probe");
const ESC = "\x1b";
const osc8 = (uri) => `${ESC}]8;;${uri}${ESC}\\`;
const lines = [
	"Open https://example.com/docs and src/app/main.ts:42 or lib/util.go:7:3 now",
	`See ${osc8("https://example.org/x")}the linked text${osc8("")} and plain text after`,
	`wrap: https://example.com/${"a".repeat(90)}/end tail`,
	`token ghp_${"A".repeat(36)} key AKIA${"B".repeat(16)} end`,
	"--- a/foo/bar.ts",
	"+++ b/foo/bar.ts",
	"sha 0123456789abcdef uuid 123e4567-e89b-12d3-a456-426614174000 #ff8800 10.0.0.1 0xdeadbeef 123456",
	`[docs](https://example.com/md) sha256:${"c".repeat(64)}`,
];
await mkdir(dir, { recursive: true });
await writeFile(path.join(dir, "recording"), Buffer.from(`${lines.join("\r\n")}\r\n`, "utf8"));
await writeFile(path.join(dir, "size.json"), `${JSON.stringify([{ offset: 0, cols: 80, rows: 24 }])}\n`);
process.stdout.write(`wrote ${dir}\n`);
