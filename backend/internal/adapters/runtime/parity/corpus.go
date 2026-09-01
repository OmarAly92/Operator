//go:build parity

package parity

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
)

type altVector struct {
	Rows        int    `json:"rows"`
	Cols        int    `json:"cols"`
	InputBase64 string `json:"inputBase64"`
}

type redrawVector struct {
	Columns int   `json:"columns"`
	Rows    int   `json:"rows"`
	Bytes   []int `json:"bytes"`
}

func repoRoot() string {
	_, thisFile, _, _ := runtime.Caller(0)
	return filepath.Join(filepath.Dir(thisFile), "..", "..", "..", "..", "..")
}

func loadAltVector(name string) Scenario {
	path := filepath.Join(repoRoot(), "packages", "terminal", "protocol", "alt-vectors", name+".json")
	data, err := os.ReadFile(path)
	if err != nil {
		panic(fmt.Sprintf("parity: read %s: %v", path, err))
	}
	var v altVector
	if err := json.Unmarshal(data, &v); err != nil {
		panic(fmt.Sprintf("parity: decode %s: %v", path, err))
	}
	bytes, err := base64.StdEncoding.DecodeString(v.InputBase64)
	if err != nil {
		panic(fmt.Sprintf("parity: decode inputBase64 for %s: %v", path, err))
	}
	return Scenario{
		Name:  name,
		Bytes: bytes,
		Cols:  v.Cols,
		Rows:  v.Rows,
	}
}

func loadRedrawVector(name string) Scenario {
	path := filepath.Join(repoRoot(), "packages", "terminal", "protocol", "redraw-vectors", name+".json")
	data, err := os.ReadFile(path)
	if err != nil {
		panic(fmt.Sprintf("parity: read %s: %v", path, err))
	}
	var v redrawVector
	if err := json.Unmarshal(data, &v); err != nil {
		panic(fmt.Sprintf("parity: decode %s: %v", path, err))
	}
	bytes := make([]byte, len(v.Bytes))
	for i, b := range v.Bytes {
		bytes[i] = byte(b)
	}
	return Scenario{
		Name:  name,
		Bytes: bytes,
		Cols:  v.Columns,
		Rows:  v.Rows,
	}
}

func Corpus() []Scenario {
	scenarios := []Scenario{
		loadAltVector("htop-frame"),
		loadAltVector("vim-open"),
		loadAltVector("less-page"),
		loadAltVector("less-back"),
		loadRedrawVector("agent-cli-idle"),
		{
			Name:  "plain-prompt",
			Bytes: []byte("$ echo hi\r\nhi\r\n$ "),
			Cols:  80,
			Rows:  24,
		},
		{
			Name:  "cursor-addressing",
			Bytes: []byte("AAAA\x1b[1;1HB"),
			Cols:  80,
			Rows:  24,
		},
		{
			Name:  "alt-screen-enter-draw-leave",
			Bytes: []byte("\x1b[?1049h\x1b[2J\x1b[1;1Hframe\x1b[?1049l"),
			Cols:  80,
			Rows:  24,
		},
		{
			Name:  "scroll-region",
			Bytes: append([]byte("\x1b[2;10r\x1b[10;1H"), scrollRegionLines()...),
			Cols:  80,
			Rows:  24,
		},
		{
			Name:  "wide-characters",
			Bytes: []byte("日本語テスト"),
			Cols:  80,
			Rows:  24,
		},
		{
			Name:     "resize-mid-stream",
			Bytes:    []byte("AAAA\x1b[1;1HB"),
			Cols:     80,
			Rows:     24,
			ResizeAt: 4,
			NewCols:  100,
			NewRows:  30,
		},
	}
	return scenarios
}

func scrollRegionLines() []byte {
	var out []byte
	for i := 1; i <= 20; i++ {
		out = append(out, []byte(fmt.Sprintf("line %02d\r\n", i))...)
	}
	return out
}
