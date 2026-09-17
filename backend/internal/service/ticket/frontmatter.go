package ticket

import (
	"bytes"
	"errors"
	"fmt"
	"strings"

	"gopkg.in/yaml.v3"
)

type frontmatter struct {
	Title   string `yaml:"title"`
	Brief   string `yaml:"brief"`
	Created string `yaml:"created"`
}

var fence = []byte("---\n")

func parseFrontmatter(content []byte) (frontmatter, string, error) {
	content = bytes.ReplaceAll(content, []byte("\r\n"), []byte("\n"))
	if !bytes.HasPrefix(content, fence) {
		return frontmatter{}, string(content), nil
	}
	rest := content[len(fence):]
	end := bytes.Index(rest, []byte("\n---"))
	if end < 0 {
		return frontmatter{}, "", errors.New("frontmatter: unterminated fence")
	}
	head := rest[:end+1]
	body := rest[end+len("\n---"):]
	body = bytes.TrimPrefix(body, []byte("\n"))
	var fm frontmatter
	if err := yaml.Unmarshal(head, &fm); err != nil {
		return frontmatter{}, "", fmt.Errorf("frontmatter: %w", err)
	}
	return fm, string(body), nil
}

func titleOf(fm frontmatter, body, fallback string) string {
	if t := strings.TrimSpace(fm.Title); t != "" {
		return t
	}
	for _, line := range strings.Split(body, "\n") {
		if strings.HasPrefix(line, "# ") {
			if t := strings.TrimSpace(strings.TrimPrefix(line, "# ")); t != "" {
				return t
			}
		}
	}
	return fallback
}
