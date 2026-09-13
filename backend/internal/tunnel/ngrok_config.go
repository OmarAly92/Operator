package tunnel

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

const ngrokConfigIndent = "    "

func DefaultNgrokConfigPath() string {
	if runtime.GOOS == "windows" {
		if dir := os.Getenv("LOCALAPPDATA"); dir != "" {
			return filepath.Join(dir, "ngrok", "ngrok.yml")
		}
	}
	dir, err := os.UserConfigDir()
	if err != nil {
		return ""
	}
	return filepath.Join(dir, "ngrok", "ngrok.yml")
}

func writeNgrokWebAddr(path string, controlPort int) error {
	existing, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(mergeNgrokWebAddr(string(existing), controlPort)), 0o600)
}

func mergeNgrokWebAddr(existing string, controlPort int) string {
	webAddr := fmt.Sprintf("%sweb_addr: 127.0.0.1:%d", ngrokConfigIndent, controlPort)

	var head, agentBody []string
	hasVersion, inAgent := false, false

	for _, raw := range strings.Split(existing, "\n") {
		line := strings.TrimRight(raw, "\r")
		if strings.TrimSpace(line) == "" {
			continue
		}
		if strings.HasPrefix(line, " ") || strings.HasPrefix(line, "\t") {
			if inAgent {
				if strings.HasPrefix(strings.TrimSpace(line), "web_addr:") {
					continue
				}
				agentBody = append(agentBody, line)
				continue
			}
			head = append(head, line)
			continue
		}
		inAgent = strings.HasPrefix(line, "agent:")
		if inAgent {
			continue
		}
		if strings.HasPrefix(line, "version:") {
			hasVersion = true
		}
		head = append(head, line)
	}

	var out []string
	if !hasVersion {
		out = append(out, `version: "3"`)
	}
	out = append(out, head...)
	out = append(out, "agent:", webAddr)
	out = append(out, agentBody...)
	return strings.Join(out, "\n") + "\n"
}
