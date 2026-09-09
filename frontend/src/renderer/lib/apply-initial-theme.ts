import { applyDocumentSkin, readStoredThemeStyle, resolveTheme } from "./theme";
import { applyTerminalBackground, readStoredTerminalBackground } from "./terminal-background";

// Runs as the first main.tsx import, before styles.css, so data-theme and
// data-style-theme are set before token CSS paints (avoids a flash on load).
applyDocumentSkin(readStoredThemeStyle(), resolveTheme());
applyTerminalBackground(readStoredTerminalBackground());
