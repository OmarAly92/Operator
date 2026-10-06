package ptyhost

import "github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"

const mirrorColdRingBytes = 32 << 20

var mirrorLimits = vtwasm.Limits{Rows: 200_000, Bytes: 128 << 20, ColdRingBytes: mirrorColdRingBytes}
