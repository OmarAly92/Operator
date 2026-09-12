# Public Tunnel Probes — Measured Evidence

**Date:** 2026-09-12
**Host:** macOS 25.5.0, arm64, system resolver 8.8.8.8
**Versions:** `cloudflared` 2026.3.0 (built 2026-03-06), `ngrok` 3.39.6
**Method:** a local Python HTTP server (JSON endpoint, chunked SSE endpoint, real
WebSocket handshake + frame echo) exposed through each tunnel, then exercised
from this machine over the public URL. Every tunnel was torn down at the end of
its probe; `pgrep -fl "cloudflared|ngrok"` was empty afterwards.

Probe scripts lived in the session scratchpad and were not committed — they are
throwaway. What matters is reproduced below.

## 1. Timing to reachable

| Milestone | ngrok | cloudflared quick tunnel |
| --- | --- | --- |
| Public URL known to the agent | 1.0s | 5.6s |
| Tunnel reports itself ready | ~1s (`tunnel session started`) | 6.1s (`/ready` → `readyConnections:1`) |
| Hostname resolves in DNS | immediate | 8.3s |
| First HTTP 200 through the tunnel | immediate, first attempt | 8.7s |

## 2. Machine-readable URL sources

Neither provider requires scraping human-readable log banners.

**ngrok** — agent API, default `127.0.0.1:4040`:

```
GET /api/tunnels  →  {"tunnels":[{"public_url":"https://imagines-livestock-widely.ngrok-free.dev", ...}]}
```

The URL is also emitted in `--log=stdout --log-format=json` output, on
**stdout**, within ~1s.

**cloudflared** — metrics server, address set by `--metrics 127.0.0.1:<port>`:

```
GET /quicktunnel  →  {"hostname":"cradle-compatibility-biology-saskatchewan.trycloudflare.com"}
GET /ready        →  {"status":200,"readyConnections":1,"connectorId":"c687b758-..."}
```

The ASCII banner carrying the URL goes to **stderr**, not stdout.

## 3. WebSocket — both providers pass

Identical result for both, against a real handshake (`Sec-WebSocket-Accept`
computed from the client key) followed by a masked text frame:

```
status: HTTP/1.1 101 Switching Protocols
echo:   "echo:hello"
```

## 4. SSE — ngrok streams, cloudflared quick tunnels buffer

Server emits `data: tick-N` once per second for 5 seconds. Arrival times as
observed by the client, seconds from first byte:

| Event | ngrok | cloudflared |
| --- | --- | --- |
| tick-0 | 0.28 | 5.28 |
| tick-1 | 1.28 | 5.28 |
| tick-2 | 2.29 | 5.28 |
| tick-3 | 3.29 | 5.28 |
| tick-4 | 4.30 | 5.28 |

This was measured twice against cloudflared. The first run used a
close-delimited body (no `Content-Length`, no chunking), which Cloudflare could
legitimately buffer, so the server was corrected to emit **`Transfer-Encoding:
chunked` with a flush per event** — the way a flushed `net/http` SSE handler
behaves. cloudflared buffered identically both times; ngrok streamed both times,
against the same corrected server. Quick tunnels route through a Cloudflare
Worker (`Cf-Worker: trycloudflare.com` appears in the origin's headers), which
is the presumed cause.

**Scope of this finding:** it is measured for *quick* (account-less) tunnels
only. A named tunnel on a real Cloudflare zone was not tested — that needs an
account, which is the thing the quick-tunnel path exists to avoid.

## 5. Headers the origin receives

**Through cloudflared** (client IP redacted to its first two octets):

```
Cf-Connecting-Ip: 156.204.x.x
X-Forwarded-For:  156.204.x.x
X-Forwarded-Proto: https
Cdn-Loop: cloudflare; loops=1; subreqs=1
Cf-Worker: trycloudflare.com
Cf-Ipcountry: EG
```

**Through ngrok:**

```
X-Forwarded-For:   156.204.x.x
X-Forwarded-Host:  imagines-livestock-widely.ngrok-free.dev
X-Forwarded-Proto: https
```

Both carry the true client IP. cloudflared additionally supplies
`Cf-Connecting-Ip`, which is single-valued and therefore the safer of the two to
parse.

## 6. ngrok free-plan interstitial

Same URL, same path, differing only in `User-Agent`:

| User-Agent | Response |
| --- | --- |
| `Dart/3.9 (dart:io)` | `{"ok":true}`, HTTP 200 — reaches the origin |
| iPhone Safari UA | ngrok's HTML warning page — **never reaches the origin** |

The origin logged exactly one request during that pair, confirming the browser-UA
request was terminated at ngrok's edge. Dio's default UA passes *today*, but this
is an edge heuristic on User-Agent, not a contract, and the preview WebView sends
a browser UA. `ngrok-skip-browser-warning: 1` suppresses it.

## 7. Local resolver trap (cost an hour of wrong conclusions)

An early probe reported the cloudflared hostname as "never resolves" for 180s
while `dig +short <host>` returned `104.16.230.132` immediately. Cause: the probe
called `getaddrinfo` on the hostname *before the DNS record existed*, and macOS
mDNSResponder negative-cached the NXDOMAIN for minutes. `dig` bypasses that cache.
Re-probing after waiting for `dig` gave first-200 at 8.7s.

**Design consequence:** readiness must be probed via the provider's own local
API, never by resolving the public hostname from the desktop. Doing the latter
both lies and poisons the user's resolver cache.
