import { cd } from "./cd.js";
import { docker } from "./docker.js";
import { git } from "./git.js";
import type { CommandSpec } from "../signature.js";

export const defaultSignatures: readonly CommandSpec[] = [cd, git, docker];

export { cd, docker, git };
