import { createHash, generateKeyPairSync, sign, verify, createPublicKey, createPrivateKey } from "node:crypto";
import { readdir, readFile, rm, writeFile, mkdir, mkdtemp } from "node:fs/promises";
import { execFile } from "node:child_process";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export async function generateEphemeralKeypair(directory) {
  await mkdir(directory, { recursive: true });
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const privatePem = privateKey.export({ type: "pkcs8", format: "pem" });
  const publicPem = publicKey.export({ type: "spki", format: "pem" });
  const privatePath = path.join(directory, "private.key");
  const publicPath = path.join(directory, "public.key");
  await writeFile(privatePath, privatePem, { mode: 0o600 });
  await writeFile(publicPath, publicPem);
  const publicDer = publicKey.export({ type: "spki", format: "der" });
  const fingerprint = createHash("sha256").update(publicDer).digest("hex");
  return { privatePath, publicPath, fingerprint, privatePem, publicPem };
}

export async function signFixture({ fixturePath, privateKeyPath, signaturePath }) {
  const [fixtureBytes, privatePem] = await Promise.all([readFile(fixturePath), readFile(privateKeyPath, "utf8")]);
  const privateKey = createPrivateKey(privatePem);
  const signature = sign(null, fixtureBytes, privateKey);
  await writeFile(signaturePath, signature);
  return signature;
}

export async function verifyFixture({ fixturePath, signaturePath, publicKeyPath }) {
  const [fixtureBytes, signature, publicPem] = await Promise.all([
    readFile(fixturePath),
    readFile(signaturePath),
    readFile(publicKeyPath, "utf8"),
  ]);
  const publicKey = createPublicKey(publicPem);
  if (publicKey.asymmetricKeyType !== "ed25519") throw new Error("public key must be Ed25519");
  const valid = verify(null, fixtureBytes, publicKey, signature);
  if (!valid) throw new Error("signature is invalid");
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
    const { privatePath, publicPath } = await generateEphemeralKeypair(keyDir);
    const signaturePath = path.join(outputDir, "fixture.sig");
    await mkdir(outputDir, { recursive: true });
    await signFixture({ fixturePath, privateKeyPath: privatePath, signaturePath });
    await verifyFixture({ fixturePath, signaturePath, publicKeyPath: publicPath });
    const publicPem = await readFile(publicPath, "utf8");
    const signatureValid = true;
    const evidence = {
      valid: true,
      signatureValid,
      privateKeyLeaked: false,
      publicKey: publicPem.slice(0, 64),
    };
    await assertNoPrivateKeyLeak({ outputDir, privateKeyPath: privatePath, gitRoot });
    const files = await walkFiles(outputDir);
    for (const file of files) {
      if (path.basename(file) === "private.key" || file.includes("private.key")) {
        throw new Error("private key entered output directory");
      }
    }
    result = { valid: true, signatureValid: true, privateKeyLeaked: false, publicFingerprint: createHash("sha256").update(publicPem).digest("hex") };
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
