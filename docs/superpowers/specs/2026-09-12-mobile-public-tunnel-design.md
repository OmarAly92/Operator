# Mobile Public Tunnel — Design

**Date:** 2026-09-12
**Status:** Approved design, not yet implemented
**Goal:** Add one switch to the Connect Mobile dialog that makes the mobile
bridge reachable from outside the LAN, so pairing is still "press the switch,
scan the QR, connected" when the phone is on cellular or another network.

Measurements cited throughout come from
[`docs/superpowers/evidence/mobile-public-tunnel-probes.md`](../evidence/mobile-public-tunnel-probes.md),
recorded on 2026-09-12 against `ngrok` 3.39.6 and `cloudflared` 2026.3.0.

## 1. Problem

Connect Mobile pairs a phone over a LAN listener. `AutopickLANIP`
(`backend/internal/mobilebridge/netiface.go:58`) hands back a private address,
and `pairingPayload`
(`frontend/src/renderer/components/ConnectMobileModal.tsx:43`) puts that address
into the QR. Off the LAN, the QR is worthless.

The dialog's existing answer is the Tailscale tab, and it is manual by
construction: the code comment on `ConnectMobileSetup`
(`frontend/src/renderer/components/settings/ConnectMobileSetup.tsx:17`–`:21`)
records why — the QR can only ever carry the LAN address, because
`AutopickLANIP` skips `utun*` interfaces and rejects Tailscale's CGNAT range.
So remote access today means installing Tailscale on both devices, running
`tailscale ip -4`, and typing three values into the phone.

## 2. What this adds

A second switch in the Connect Mobile dialog, under "Enable mobile": while the
bridge is on, flipping it starts a public HTTPS tunnel to the bridge port and
swaps the QR to the tunnel URL. One scan, no typing, works from anywhere.

Three properties are requirements, not nice-to-haves, and the design is judged
against them:

**Easy** — one switch, one scan, and ideally *one* scan ever. §5 covers why the
ngrok path can pair once and keep working, and why the cloudflared path cannot.

**Reliable** — the tunnel must still be up when the user is away from the
machine, which means liveness has to be observed rather than assumed and
failures have to self-heal. §7 covers health probing and reconnection.

**Practical** — the feature has to work in the scenario that motivated it: the
user is already outside the network when they need it. That rules out any design
requiring physical presence at the desk to arm the tunnel. §9 covers
persistence.

## 3. Provider choice, and the two measurements that shaped it

One `Provider` seam with two implementations, preferring ngrok when an
authtoken is saved and falling back to a cloudflared quick tunnel so the very
first press works with no account at all.

Three findings from §4, §6 and §8 of the evidence file drive the design more
than the speed numbers do:

**cloudflared quick tunnels buffer SSE.** Five one-second events all arrived
together. This was measured twice — the second time against a server corrected
to emit `Transfer-Encoding: chunked` with a flush per event, so it is not a
malformed-response artifact. ngrok streamed the same server correctly.

This does **not** block the mobile client, and the reason is specific: the
Flutter app consumes no SSE at all. Session patches, terminal events and block
events all arrive over the single mux WebSocket
(`packages/mobile/lib/core/mux/mux_client.dart:78`–`:81`), and WebSocket upgrade
plus framing was verified working through **both** providers. `EndPoints.events`
(`packages/mobile/lib/core/api/api_request_helpers/end_points.dart:12`) is
declared and has zero call sites in the app.

Two consequences, both binding:

- The cloudflared path is sanctioned for the **mobile client only**. The
  desktop's event stream must never be routed through a quick tunnel.
- If mobile ever adopts SSE, the cloudflared fallback breaks silently — live
  updates would arrive in batches, with no error anywhere. A test must fail the
  moment an SSE consumer appears in the mobile app.

**ngrok's URL is stable; cloudflared's is not.** Four independent ngrok agent
sessions on this account returned the identical hostname, while every
cloudflared quick tunnel returned a fresh one (evidence §8). See §5 — this is
the difference between pairing once and re-pairing on every restart, and it is
the strongest reason ngrok is the preferred path rather than merely the faster
one.

**ngrok's free interstitial is UA-gated.** A request with Dio's
`Dart/3.9 (dart:io)` UA reached the origin; the same request with an iPhone
Safari UA was answered by ngrok's HTML warning page and never reached the origin
at all. Dio passes today, but that is an edge heuristic, not a contract, and the
preview WebView does send a browser UA. So `ngrok-skip-browser-warning: 1` is an
unconditional default header on the mobile client, not a fix applied after
something breaks.

## 4. `backend/internal/tunnel`

A new package holding a `Manager` and two `Provider` implementations. It owns no
httpd or daemon types, matching `mobilebridge`'s framing
(`backend/internal/mobilebridge/config.go:1`–`:3`).

`Manager` is modeled on `previewserver.Manager`
(`backend/internal/previewserver/manager.go`), which already solves this exact
shape of problem and should not be re-solved in a second style. Reused
mechanics, with the precedent to copy:

| Concern | Precedent |
| --- | --- |
| Start/Stop/Status over a supervised child | `manager.go:192`, `:355`, `:453` |
| Graceful stop then force-kill after a grace period | `forceStopAfterGrace` (`manager.go:805`) |
| Bounded stdout retention for diagnostics | `lineBuffer` (`manager.go:928`) |
| Persisted PIDs, orphans reaped on daemon start | `persistProcessesLocked` (`manager.go:866`), `reapPersistedProcesses` (`manager.go:830`) |
| Reserving a loopback port | `reservePort` (`manager.go:746`) |

Orphan reaping is not optional here. An unreaped `previewserver` child is a
stale localhost port; an unreaped tunnel child is a **public URL into the user's
machine that outlives the app that created it**.

The `Provider` seam:

```go
type Provider interface {
	Name() string
	Binary() BinarySpec
	Args(localPort, controlPort int) []string
	PublicURL(ctx context.Context, controlPort int) (string, error)
	Ready(ctx context.Context, controlPort int) (bool, error)
	Healthy(ctx context.Context, controlPort int) (bool, error)
	ClientIPHeader() string
}
```

`PublicURL` and `Ready`/`Healthy` query each provider's own local API — no log scraping.
Both endpoints are recorded in §2 of the evidence file: ngrok's
`/api/tunnels` → `public_url`, and cloudflared's `/quicktunnel` → `hostname`
with `/ready` → `readyConnections`. `ClientIPHeader` returns
`Cf-Connecting-Ip` for cloudflared (single-valued, so safer to parse) and
`X-Forwarded-For` for ngrok.

Readiness is probed **only** through those local APIs. It must never be probed
by resolving the public hostname from the desktop: §7 of the evidence file
records that resolving the name before the DNS record exists negative-caches
NXDOMAIN in macOS mDNSResponder for minutes, which both reports a false failure
and degrades the user's own resolver.

### ngrok control-port collision

ngrok's agent API defaults to `127.0.0.1:4040`, which collides with a user's own
running ngrok. `ngrok http` exposes no flag for it (verified: `--api-addr` is
rejected as an unknown flag, and `ngrok http --help` lists no equivalent), so
the address has to come from a config file — ours, carrying a reserved port,
passed as an additional `--config` alongside the user's own so their authtoken
still merges in.

**The exact v3 config key for that address is not known.** It was not verified,
and it is the first thing the implementation plan checks; everything else in
this section rests on measurements. Do not write a key name into code from
memory. If no such key exists, the fallback is to reserve 4040 ourselves and
fail with a clear message when it is already taken.

## 5. Pair once: URL stability is the whole feature

The measured difference between the two providers is not speed, it is whether
the user ever has to scan again.

Four independent ngrok sessions on this account returned the identical hostname;
every cloudflared quick tunnel returned a new one (evidence §8). Since the
mobile app persists `ServerConfig`, a stable URL means the phone is paired
**once, permanently** — flip the switch today and the phone that scanned it last
month still connects. A changing URL means re-scanning after every restart,
which is not meaningfully easier than the Tailscale typing this feature
replaces.

So the two providers are not interchangeable, and the preference order is a
consequence of that rather than a taste:

| | ngrok | cloudflared quick tunnel |
| --- | --- | --- |
| URL across restarts | stable (observed) | new every time |
| Pairing | once, permanently | re-scan after each restart |
| Role | the path the button takes whenever an authtoken exists | zero-setup fallback so the first press works with no account |

Three rules follow, and they are binding:

1. **Never cache the URL across runs.** Read it from the provider's local API on
   every start and re-render the QR from what comes back. Stability is then a
   benefit where it exists and costs nothing where it does not. Caching would
   turn a changed URL into a QR that silently points nowhere.
2. **Getting an authtoken in must be trivial**, since it is what unlocks
   pair-once. The dialog opens ngrok's authtoken page and offers a paste field,
   validating the token by starting a tunnel rather than by parsing it. One
   paste, once, ever — and until then the cloudflared fallback keeps the button
   working.
3. **The UI must not present the two paths as equivalent.** A user on the
   fallback who does not know their URL rotates will read a stale-URL failure as
   the feature being broken.

Whether the stability comes from a reserved domain or sticky assignment was not
established (evidence §8) — rule 1 makes that moot, which is why the spec does
not depend on the answer.

## 6. Binary acquisition

Fetched on first press into `~/.operator/bin/<provider>-<version>`, verified
against a SHA-256 pinned per provider/OS/arch, written via temp file + atomic
rename (the pattern `mobilebridge.Save` already uses,
`backend/internal/mobilebridge/config.go:58`–`:85`), `chmod 0755`. A cached
binary that fails its checksum is discarded and refetched once.

If the download itself fails — offline, corporate proxy, provider moved the
URL — the manager falls back to a matching binary already on `PATH` before
reporting failure. A user with Homebrew's `ngrok` should never be blocked by
our download infrastructure; the pinned copy is the default because it is the
version we tested, not because `PATH` is untrustworthy.

Chosen over bundling because the installer already carries a daemon and
`agent-browser` (`frontend/src-tauri/tauri.conf.json:24`–`:27`), and two more
~30MB binaries × 5 bundle targets is a real cost for a feature most launches
never use. The trade is a first-press download, which the UI shows as its own
state.

## 7. Health, reconnection, and staying up unattended

A tunnel the user depends on from a cafe has to survive a Wi-Fi blip, a laptop
wake, and a provider edge restart without anyone touching the machine. A
supervised process that is merely *alive* proves none of that: both providers
keep their process running while disconnected from their edge.

**Liveness is observed, not assumed.** `Provider.Healthy` polls the provider's
own connection state (evidence §9) — ngrok `/api/status` → `status == "online"`,
cloudflared `/ready` → `readyConnections >= 1`. Poll every 15s while `live`.
`/ready` returns 503 while still connecting, so the pre-`live` window must
tolerate that rather than read it as failure.

**Both agents already reconnect on their own**, so the manager's job is the case
the agent cannot handle: its own death. On unexpected child exit, or on the
health probe reporting not-online for two consecutive polls, restart the child
with exponential backoff — 1s, 2s, 4s, … capped at 60s — resetting the backoff
after 60s of continuous health.

**Retry forever at the ceiling; never give up silently.** A machine left running
overnight through a router reboot must come back on its own. `failed` is
reserved for causes retrying cannot fix (checksum mismatch, missing authtoken,
provider rejecting the account); a network-shaped failure stays `reconnecting`
however long it takes.

**The URL may change across a restart.** cloudflared guarantees it will. On
every successful (re)start the manager re-reads the URL and republishes it to
status, so the dialog's QR is never stale (§5, rule 1). A phone paired to the
previous URL is orphaned — §11 covers how the app must present that.

Restarts are counted and exposed (§8). A tunnel that has restarted 40 times is
not healthy, and hiding that behind a green `live` badge would make the feature
feel haunted rather than reliable.

## 8. API surface

```
POST /api/v1/mobile/tunnel/enable
POST /api/v1/mobile/tunnel/disable
```

Registered in `mountMobile` (`backend/internal/httpd/router.go:139`–`:147`)
beside the existing four, and therefore loopback-only and unreachable from a
phone: `lanControlBlock` (`backend/internal/httpd/lan_listener.go:38`) already
404s the `/api/v1/mobile` prefix on the LAN listener. A paired phone cannot open
or close a tunnel, and that stays true for the new routes by construction.

`GET /api/v1/mobile/status` grows one nested object:

```json
{ "tunnel": { "state": "off|downloading|starting|live|reconnecting|failed",
              "provider": "ngrok|cloudflared", "url": "", "error": "",
              "since": "2026-09-12T15:20:28Z", "restarts": 0 } }
```

`MobileStatusResponse` and the OpenAPI spec
(`backend/internal/httpd/apispec/openapi.yaml`, generator at
`backend/internal/httpd/apispec/specgen/build.go:744`) both need the new field
and the two new operations, and `frontend/src/api/schema.ts` is regenerated from
them.

`since` lets the renderer show how long the tunnel has been up, and
`restarts` surfaces a flapping tunnel instead of hiding it behind a `live`
badge that keeps blinking.

Enable is asynchronous: it returns immediately with `state` set, and the
renderer's existing `mobileStatusQueryKey` query
(`frontend/src/renderer/components/ConnectMobileModal.tsx:25`) polls with a
`refetchInterval` while the state is non-terminal. No new event plumbing —
worst case is ~9s of polling, per §1 of the evidence file.

## 9. Persistence and the security model

Going public changes the threat model the bridge was built for, so these
changes are part of this feature, not follow-ups.

### Persistence, and why the safer-looking choice was rejected

The tunnel's enabled state is **persisted** in `mobilebridge.State`, and the
daemon starts it automatically whenever the bridge comes up.

An earlier revision of this spec had the opposite rule — off on every daemon
start, so nothing public could outlive a reboot. It reads well and it is wrong:
arming the tunnel would require being at the machine, so the feature would be
unavailable in precisely the situation it exists for (the user is already out;
the Mac rebooted or woke up). A safety property that removes the feature's
reason to exist is not a safety property worth having.

What carries that weight instead:

- the one-time confirmation (§10), so exposure is never accidental;
- a 131-bit password, below;
- an always-visible indicator while live (§10), so it cannot be forgotten;
- one switch to revoke, and password regeneration as a second revocation path;
- `since` in status (§8), so the age of an exposure is always legible.

Orphan reaping (§4) stays load-bearing regardless: a *persisted intent* to run a
tunnel is not the same as a tunnel process nobody owns, and the second must
still be killed on startup before the first is honored.

### Longer password while tunneled

`GeneratePassword` (`backend/internal/mobilebridge/config.go:91`) returns 8
base62 characters — ~48 bits, sized for a trusted LAN. Enabling the tunnel
rotates to a 22-character password (~131 bits). The QR carries it, so the cost
to the user is zero. Length is a function of whether the tunnel is on at
generation time, and rotating on enable means the short LAN password is never
the one exposed publicly.

Rotation drops the currently paired phone, exactly as `Regenerate` does today
(`backend/internal/httpd/controllers/mobile.go:153`–`:158`) — so it happens on the
*transition* to tunneled, while the user is at the machine and looking at a
fresh QR, never on an auto-start where nobody is present to re-scan.

### Proxy-aware lockout

`sourceKey` (`backend/internal/httpd/auth.go:77`) keys the 5-fails-per-minute
lockout (`backend/internal/httpd/lan_listener.go:36`) on `RemoteAddr`. Through a
tunnel every request arrives from `127.0.0.1`, so all clients collapse into one
bucket: brute force is still throttled, but any stranger who finds the URL can
lock the owner's phone out at will. `sourceKey` must instead take the provider's
`ClientIPHeader` value — and only when **both** hold: `RemoteAddr` is loopback,
and the tunnel is running. Otherwise a LAN client could forge the header and
evade the lockout entirely. Both headers were confirmed to carry the true client
IP (evidence §5).

### Conditional warning copy

The unencrypted-LAN warning
(`backend/internal/httpd/controllers/mobile.go:12`) is wrong while tunneled —
both providers terminate TLS and the hop to the phone is HTTPS. It becomes
conditional: the existing plaintext warning on LAN, and a different one naming
public exposure while the tunnel is live.

## 10. Renderer

A second switch in the toggle stack below "Enable mobile", disabled while the
bridge is off. It is deliberately *not* a third segment beside LAN/Tailscale:
the tunnel and the LAN listener are live simultaneously, so it is a property of
the bridge, not an alternative connection method.

When `state == "live"`, the QR payload and the address row switch to the tunnel
URL; otherwise both stay on LAN values. `downloading` and `starting` render as
inline progress on the row, `reconnecting` as a distinct non-alarming state
(it self-heals; see §7), and `failed` renders `error` through the same
treatment as the existing `actionError`.

Because the tunnel now persists across restarts (§9), the dialog is no longer
the only place its state may be visible. A tunnel that is live while the user
is at the machine should be discoverable without opening Connect Mobile —
scoped here as a requirement, with the placement left to the implementation,
since the surrounding chrome is outside what this spec surveyed.

**One-time confirmation.** The first enable opens a dialog stating plainly what
becomes internet-reachable — agent spawning and terminal access, guarded by the
password carried in the QR — and requires an explicit confirm. The
acknowledgement is remembered, so every later enable is a single click. New
copy goes in `frontend/src/renderer/i18n/en.json`; `renderer-coverage.test.ts`
gates the other eight locales.

## 11. Pairing payload v2 and the mobile client

The QR grows a second shape. LAN keeps `{v:1, host, port, password}`; the tunnel
emits `{v:2, url, password}` with a full `https://…` origin.

Mobile parses both in `parsePairingPayload`
(`packages/mobile/lib/feature/pairing/logic/pairing_payload.dart`), and `v:2`
sets `secure: true`. That also fixes a live bug on the way past:
`pairing_scan_cubit.dart:39` hardcodes `secure: current?.secure ?? false`, so a
scan can never turn TLS on today regardless of payload. `ServerConfig` needs no
change — `httpBase`/`wsBase`
(`packages/mobile/lib/core/api/server_config.dart:16`, `:18`) already compose
`https`/`wss` from `secure`, with port 443.

An older app build that meets `v:2` fails closed: the existing `parsed['v'] != 1`
guard returns null. The scan screen must distinguish "unrecognized payload
version" from "not a pairing QR" and say *update the app*, or the failure reads
as a broken QR.

**A stored URL can go stale.** On the ngrok path the URL was observed stable
(evidence §8), so a phone paired once keeps working. On the cloudflared path
it changes every restart, so a phone paired against the old URL will fail
every request. The app must render that as *this desktop is unreachable —
re-scan the code*, distinguishable from a wrong password and from a sleeping
host, rather than as an indefinite spinner. This is the concrete reason §5
treats ngrok as the path that delivers pair-once.

`ngrok-skip-browser-warning: 1` joins the Dio default headers
(`packages/mobile/lib/core/api/api_request_helpers/dio_consumer.dart`) and the
preview WebView's request headers. It is inert on LAN and on cloudflared.

**Shipping consequence, stated plainly:** the desktop half is useless until a
mobile build that parses `v:2` is on the phone. This feature is not done when
the switch works — it is done when a TestFlight build understands the QR.

The 12-second Dio timeouts (`dio_consumer.dart:44`–`:45`) are deliberate and
documented in `CLAUDE.md`; measured tunnel latency gives no reason to touch
them.

## 12. Deliberately not built

- **No custom domains, and no reserved-domain provisioning.** The ngrok URL
  was observed stable on this account already (evidence §8) and is read from
  the agent on every start, so pair-once comes for free where it is available
  and nothing breaks where it is not. Attaching a domain to an account is the
  user's business, not ours.
- **No auto-expiry or periodic re-confirmation.** Explicitly chosen against:
  an expiring tunnel fails exactly when the user is away and cannot renew it,
  which is the scenario the feature exists for. The always-visible indicator
  (§10) and the one-time confirmation carry that weight instead.
- **No embedded ngrok Go SDK.** It would remove the ngrok binary download and
  the URL parsing, but cloudflared has no embeddable equivalent, so the
  zero-setup path would still need §4 — two mechanisms behind one switch. Worth
  revisiting only after the CLI path ships.
- **No IP pinning to the first authenticated phone.** It breaks when the phone
  changes towers or networks, which reads as a broken app.
- **Tailscale tab stays.** It is the right answer for anyone already on a
  tailnet and costs nothing to keep.

## 13. Testing

No test touches the network or starts a real tunnel.

- **Provider parsers** against fixtures recorded verbatim from the real outputs
  in the evidence file — ngrok `/api/tunnels`, cloudflared `/quicktunnel` and
  `/ready`, including the pre-ready `/ready` 503 that was actually observed.
- **Manager lifecycle** against a fake binary: a script that serves a canned
  control-port response and sleeps. Covers start → live, stop, force-kill after
  grace, and orphan reaping on restart.
- **Reconnection**, the reliability core, all against the fake binary with a
  fake clock — no sleeps in tests: child exits unexpectedly → `reconnecting` →
  `live`, with `restarts` incremented; backoff schedule is exact; the ceiling
  is reached and retries continue at it rather than giving up; health probe
  reporting not-online triggers a restart; `Stop` during a backoff wait exits
  promptly and schedules nothing further; a URL that changes across a restart
  is republished to status.
- **Persistence** — enabled state survives a manager restart and auto-starts
  with the bridge; a tunnel enabled before a crash does not leave an orphan
  after reaping; disabling the bridge stops the tunnel and clears the intent.
- **Auth** — table test on `sourceKey`: forwarded header honored from loopback
  with the tunnel up; ignored from a LAN address; ignored when the tunnel is
  down; malformed and multi-valued headers. Plus a test that the two new routes
  404 on the LAN listener, extending the `lanControlBlock` coverage.
- **Renderer** — QR swaps to the tunnel URL only at `live`; confirm dialog gates
  the first enable; each state renders.
- **Mobile** — `parsePairingPayload` for v1, v2, and an unknown version;
  cubit test that v2 sets `secure: true`; a test asserting the skip-browser-
  warning header is sent. Gate stays `flutter analyze` + `flutter test`.
- **SSE guard** — a test that fails if an SSE consumer appears in the mobile
  app, since that would silently break the cloudflared path (§3).

## 14. Docs

[`frontend/src/landing/content/docs/configuration/remote-access.mdx`](../../../frontend/src/landing/content/docs/configuration/remote-access.mdx)
currently instructs the reader not to expose the bridge to the public internet,
and its security-model section describes plaintext HTTP on a trusted network.
Both predate this feature and must be rewritten to describe when a tunnel is
appropriate, what the one-time confirmation is warning about, and that the
tunnel is off after every restart. Leaving the old text in place next to a
button that does the opposite is worse than either alone.

## 15. Risks

| Risk | Mitigation |
| --- | --- |
| Provider changes its local API shape | Pinned versions; parser fixtures fail loudly on upgrade |
| Quick tunnel unavailable or rate-limited | Surfaced as `failed` with the provider's message; ngrok path unaffected |
| cloudflared SSE buffering reaches a future mobile SSE consumer | §11 guard test fails on the first such consumer |
| Public URL leaks | 131-bit password; one-time confirmation; always-visible indicator; revocable by one switch or by regenerating the password |
| Tunnel persists unnoticed for months | Indicator is always visible while live (§10); `since` in status makes the age explicit |
| Flapping tunnel looks "live" | `restarts` and `reconnecting` are surfaced, not smoothed over (§7, §8) |
| ngrok free data-transfer allowance exhausted by terminal streaming | **Unverified** — the agent exposes no account or plan data (evidence §9). Implementation must confirm the allowance against the dashboard and, if it is low enough to matter, surface provider-reported quota errors as a distinct `failed` message rather than a generic one |
| Download blocked by proxy/offline | `failed` state naming the cause; LAN pairing unaffected |
