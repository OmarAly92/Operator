package claudesetup

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"sync"
)

var pathLocks sync.Map

func LockPath(path string) func() {
	value, _ := pathLocks.LoadOrStore(filepath.Clean(path), &sync.Mutex{})
	mu, _ := value.(*sync.Mutex)
	mu.Lock()
	return mu.Unlock
}

func SyncMCP(defaultConfigPath, accountConfigPath string) error {
	source, err := ReadObject(defaultConfigPath)
	if err != nil {
		return err
	}
	servers, hasServers := source["mcpServers"]
	unlock := LockPath(accountConfigPath)
	defer unlock()
	target, err := ReadObject(accountConfigPath)
	if err != nil {
		return err
	}
	current, hadServers := target["mcpServers"]
	switch {
	case !hasServers && !hadServers:
		return nil
	case !hasServers:
		delete(target, "mcpServers")
	case hadServers && reflect.DeepEqual(current, servers):
		return nil
	default:
		target["mcpServers"] = servers
	}
	return WriteObjectAtomic(accountConfigPath, target)
}

func ReadObject(path string) (map[string]any, error) {
	out := map[string]any{}
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return out, nil
	}
	if err != nil {
		return nil, fmt.Errorf("claudesetup: read %s: %w", path, err)
	}
	if len(data) == 0 {
		return out, nil
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, fmt.Errorf("claudesetup: parse %s: %w", path, err)
	}
	if out == nil {
		out = map[string]any{}
	}
	return out, nil
}

func WriteObjectAtomic(path string, value map[string]any) error {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return fmt.Errorf("claudesetup: encode %s: %w", path, err)
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".claude.json.tmp-*")
	if err != nil {
		return fmt.Errorf("claudesetup: temp for %s: %w", path, err)
	}
	name := tmp.Name()
	defer func() { _ = os.Remove(name) }()
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return fmt.Errorf("claudesetup: write %s: %w", path, err)
	}
	if err := tmp.Chmod(0o600); err != nil {
		_ = tmp.Close()
		return fmt.Errorf("claudesetup: chmod %s: %w", path, err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("claudesetup: close %s: %w", path, err)
	}
	return os.Rename(name, path)
}
