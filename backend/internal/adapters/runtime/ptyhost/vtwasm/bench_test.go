package vtwasm

import (
	"context"
	"os"
	"testing"
	"time"
)

// BenchmarkFeed16MB is the decision gate for the WASM parser. It feeds the same
// volume as the large-output perf scenario in 64KB slices, which is how the host
// will drive it.
func BenchmarkFeed16MB(b *testing.B) {
	wasmPath := os.Getenv("VT_HOST_WASM")
	if wasmPath == "" {
		b.Skip("set VT_HOST_WASM to the built vt_host.wasm")
	}
	module, err := os.ReadFile(wasmPath)
	if err != nil {
		b.Fatalf("read wasm: %v", err)
	}

	payload := make([]byte, 16<<20)
	for i := range payload {
		payload[i] = byte('a' + i%26)
		if i%80 == 79 {
			payload[i] = '\n'
		}
	}

	b.ResetTimer()
	for range b.N {
		parser, err := New(context.Background(), module, 120, 40, 1000)
		if err != nil {
			b.Fatalf("new parser: %v", err)
		}
		start := time.Now()
		for offset := 0; offset < len(payload); offset += 64 << 10 {
			end := min(offset+64<<10, len(payload))
			if err := parser.Feed(payload[offset:end]); err != nil {
				b.Fatalf("feed: %v", err)
			}
		}
		b.ReportMetric(float64(len(payload))/time.Since(start).Seconds()/(1<<20), "MB/s")
		_ = parser.Close()
	}
}
