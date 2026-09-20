package ptyhost

import "github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"

var mirrorLimits = vtwasm.Limits{Rows: 200_000, Bytes: 128 << 20}
