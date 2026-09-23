export const RETAINED_TERMINAL_UNLOAD_MS = 30 * 60_000;
// Kitty's `notify_on_cmd_finish unfocused 10.0`
// (kitty/kitty/options/definition.py): a command only earns a notification once
// it has run long enough that the user has plausibly looked away.
export const BLOCK_NOTIFY_AFTER_MS = 10_000;
export const UNLOADED_SHELL_REWATCH_BASE_MS = 500;
export const UNLOADED_SHELL_REWATCH_MAX_MS = 8_000;
