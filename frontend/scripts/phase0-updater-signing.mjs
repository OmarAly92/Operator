import { createHash, createPublicKey, verify } from "node:crypto";
import { copyFile, readdir, readFile, rm, writeFile, mkdir, mkdtemp } from "node:fs/promises";
import { execFile } from "node:child_process";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const tauriCliPath = fileURLToPath(new URL("../node_modules/@tauri-apps/cli/tauri.js", import.meta.url));
const tauriCliPackagePath = fileURLToPath(new URL("../node_modules/@tauri-apps/cli/package.json", import.meta.url));
const PINNED_TAURI_CLI_VERSION = "2.11.4";

function decodeTauriMinisignMaterial(value, label) {
  const encoded = value.trim();
  if (!/^[A-Za-z0-9+/]+=*$/.test(encoded)) throw new Error(`Tauri signer did not produce a minisign ${label}`);
  const decoded = Buffer.from(encoded, "base64").toString("utf8");
  if (!decoded.startsWith("untrusted comment:")) throw new Error(`Tauri signer did not produce a minisign ${label}`);
  return decoded.trimEnd().split("\n");
}

function assertTauriMinisignMaterial(value, label) {
  decodeTauriMinisignMaterial(value, label);
  return value.trim();
}

export async function generateEphemeralKeypair(directory, dependencies = {}) {
  await mkdir(directory, { recursive: true });
  const privatePath = path.join(directory, "private.key");
  const publicPath = `${privatePath}.pub`;
  await (dependencies.execFile ?? execFileAsync)(process.execPath, [tauriCliPath, "signer", "generate", "--ci", "--password", "", "--write-keys", privatePath]);
  const publicKey = await readFile(publicPath, "utf8");
  assertTauriMinisignMaterial(publicKey, "public key");
  const fingerprint = createHash("sha256").update(publicKey).digest("hex");
  return { privatePath, publicPath, fingerprint, publicKey };
}

export async function signFixture({ fixturePath, privateKeyPath, signaturePath }, dependencies = {}) {
  await (dependencies.execFile ?? execFileAsync)(process.execPath, [tauriCliPath, "signer", "sign", "--password", "", "--private-key-path", privateKeyPath, fixturePath]);
  const generatedSignaturePath = `${fixturePath}.sig`;
  const signature = await readFile(generatedSignaturePath, "utf8");
  assertTauriMinisignMaterial(signature, "signature");
  if (path.resolve(generatedSignaturePath) !== path.resolve(signaturePath)) await copyFile(generatedSignaturePath, signaturePath);
  return signature;
}

export async function verifyFixture({ fixturePath, signaturePath, publicKeyPath }) {
  const [fixtureBytes, signature, publicKey] = await Promise.all([readFile(fixturePath), readFile(signaturePath, "utf8"), readFile(publicKeyPath, "utf8")]);
  const publicLines = decodeTauriMinisignMaterial(publicKey, "public key");
  const signatureLines = decodeTauriMinisignMaterial(signature, "signature");
  if (publicLines.length !== 2 || signatureLines.length !== 4 || !signatureLines[2].startsWith("trusted comment: ")) throw new Error("Tauri updater signing materials are invalid");
  const publicPacket = Buffer.from(publicLines[1], "base64");
  const signaturePacket = Buffer.from(signatureLines[1], "base64");
  const globalSignature = Buffer.from(signatureLines[3], "base64");
  if (publicPacket.length !== 42 || publicPacket.subarray(0, 2).toString("ascii") !== "Ed" || signaturePacket.length !== 74 || signaturePacket.subarray(0, 2).toString("ascii") !== "ED" || globalSignature.length !== 64 || !publicPacket.subarray(2, 10).equals(signaturePacket.subarray(2, 10))) {
    throw new Error("Tauri updater signing materials are invalid");
  }
  const derPrefix = Buffer.from("302a300506032b6570032100", "hex");
  const verifyingKey = createPublicKey({ key: Buffer.concat([derPrefix, publicPacket.subarray(10)]), format: "der", type: "spki" });
  const artifactDigest = createHash("blake2b512").update(fixtureBytes).digest();
  const artifactValid = verify(null, artifactDigest, verifyingKey, signaturePacket.subarray(10));
  const trustedComment = signatureLines[2].slice("trusted comment: ".length);
  const commentValid = verify(null, Buffer.concat([signaturePacket.subarray(10), Buffer.from(trustedComment)]), verifyingKey, globalSignature);
  if (!artifactValid || !commentValid) throw new Error("signature is invalid");
  return true;
}

async function walkFiles(directory, files = []) {
  let entries = [];
  try {
    entries = await readdir(directory, { withFileTypes: true });
  } catch (error) {
    if (error?.code === "ENOENT") return files;
    throw error;
  }
  for (const entry of entries) {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) await walkFiles(full, files);
    else if (entry.isFile()) files.push(full);
  }
  return files;
}

export async function assertNoPrivateKeyLeak({ outputDir, privateKeyPath, gitRoot }) {
  const privateBytes = await readFile(privateKeyPath, "utf8").catch(() => "");
  const privateMarker = "PRIVATE KEY";
  const files = await walkFiles(outputDir);
  for (const file of files) {
    const content = await readFile(file, "utf8").catch(() => "");
    if (content.includes(privateMarker) || (privateBytes && content.includes(privateBytes.slice(0, 64)))) {
      throw new Error(`private key material leaked into output: ${path.relative(outputDir, file)}`);
    }
    const raw = await readFile(file).catch(() => Buffer.alloc(0));
    if (privateBytes && raw.includes(Buffer.from(privateBytes.slice(0, 32)))) {
      throw new Error(`private key material leaked into output: ${path.relative(outputDir, file)}`);
    }
  }
  if (gitRoot) {
    try {
      const { stdout } = await execFileAsync("git", ["status", "--porcelain", "--", outputDir], { cwd: gitRoot });
      if (stdout && stdout.includes("private.key")) {
        throw new Error("private key is tracked by git");
      }
    } catch (error) {
      if (error?.message?.includes("private key")) throw error;
    }
    try {
      const { stdout } = await execFileAsync("git", ["ls-files", "--", outputDir], { cwd: gitRoot });
      if (stdout && stdout.includes("private.key")) {
        throw new Error("private key is tracked by git");
      }
    } catch (error) {
      if (error?.message?.includes("private key")) throw error;
    }
  }
  return true;
}

export async function runEphemeralSigningFlow({ tmpDir, fixturePath, outputDir, gitRoot }) {
  const keyDir = await mkdtemp(path.join(tmpDir, "ephemeral-keys-"));
  let result;
  try {
    const cliPackage = JSON.parse(await readFile(tauriCliPackagePath, "utf8"));
    if (cliPackage.version !== PINNED_TAURI_CLI_VERSION) throw new Error(`Tauri CLI must be pinned to ${PINNED_TAURI_CLI_VERSION}`);
    const { privatePath, publicPath, fingerprint } = await generateEphemeralKeypair(keyDir);
    const signaturePath = path.join(outputDir, "fixture.sig");
    await mkdir(outputDir, { recursive: true });
    await signFixture({ fixturePath, privateKeyPath: privatePath, signaturePath });
    await verifyFixture({ fixturePath, signaturePath, publicKeyPath: publicPath });
    await copyFile(publicPath, path.join(outputDir, "public.key"));
    await copyFile(fixturePath, path.join(outputDir, "fixture.tar"));
    await assertNoPrivateKeyLeak({ outputDir, privateKeyPath: privatePath, gitRoot });
    const files = await walkFiles(outputDir);
    for (const file of files) {
      if (path.basename(file) === "private.key" || file.includes("private.key")) {
        throw new Error("private key entered output directory");
      }
    }
    result = {
      valid: true,
      signatureValid: true,
      privateKeyLeaked: false,
      format: "tauri-minisign",
      signer: `@tauri-apps/cli@${cliPackage.version}`,
      publicKeyFingerprint: fingerprint,
      signatureSha256: createHash("sha256").update(await readFile(signaturePath)).digest("hex"),
    };
    await writeFile(path.join(outputDir, "updater-signing-evidence.json"), `${JSON.stringify(result, null, "\t")}\n`, "utf8");
  } finally {
    await rm(keyDir, { recursive: true, force: true });
  }
  return result;
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const flag = argv[i];
    if (flag === "--tmp-dir") {
      args.tmpDir = argv[i + 1];
      i += 1;
    } else if (flag === "--fixture") {
      args.fixture = argv[i + 1];
      i += 1;
    } else if (flag === "--output") {
      args.output = argv[i + 1];
      i += 1;
    } else if (flag === "--git-root") {
      args.gitRoot = argv[i + 1];
      i += 1;
    } else if (flag === "--help" || flag === "-h") {
      args.help = true;
    } else if (flag.startsWith("--")) {
      throw new Error(`unknown flag: ${flag}`);
    }
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    process.stdout.write("Usage: node scripts/phase0-updater-signing.mjs --fixture <path> --output <dir> [--tmp-dir <dir>] [--git-root <dir>]\n");
    return;
  }
  if (!args.fixture || !args.output) {
    throw new Error("--fixture and --output are required");
  }
  const tmpDir = args.tmpDir || os.tmpdir();
  const gitRoot = args.gitRoot || fileURLToPath(new URL("../../", import.meta.url));
  const result = await runEphemeralSigningFlow({ tmpDir, fixturePath: args.fixture, outputDir: args.output, gitRoot });
  process.stdout.write(`signature valid: ${result.signatureValid}\n`);
  process.stdout.write(`private key leaked: ${result.privateKeyLeaked}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  });
}
