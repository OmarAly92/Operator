package vtwasm

import _ "embed"

//go:embed assets/vt_host.wasm
var Module []byte
