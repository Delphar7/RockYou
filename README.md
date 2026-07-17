# RockYou

A Roku remote for iPhone, iPad, Mac, and Apple Watch, built on a clean-room
implementation of Roku's undocumented ECP-2 WebSocket protocol.

Roku's public control API (ECP-1, plain HTTP on port 8060) is unauthenticated —
and for exactly that reason, newer Roku firmware ships a "Limited Mode" that
answers it with HTTP 403. Roku's own mobile app keeps working because it speaks
a second, undocumented protocol: ECP-2, an authenticated WebSocket session on
the same port. This repository documents that protocol and implements it from
observed behavior: the challenge-response authentication, the event
subscription model, the request/response correlation scheme, and the quirks
that only show up on real hardware. The protocol reference lives in
[Resources/Docs/Protocol.md](Resources/Docs/Protocol.md) and is licensed MPL-2.0
specifically so it can be reused outside this app.

## How it works

**Discovery.** Devices are found via SSDP multicast (`239.255.255.250:1900`,
search target `roku:ecp`) using `NWConnectionGroup`, with a subnet-scan
fallback that HTTP-probes `.1–.254` on local interfaces (max 32 concurrent)
for networks where multicast is filtered. Results stream in as found, are
cached across launches, and devices unseen for 72 hours are pruned.
([RockYou/Network/RokuDiscoveryService.swift](RockYou/Network/RokuDiscoveryService.swift))

**Protocol.** Each device gets an actor-isolated WebSocket client
(`ws://{ip}:8060/ecp-session`, subprotocol `ecp-2`). After the SHA-1
challenge-response handshake, the client subscribes to power, volume, and
media-player events; commands are JSON messages correlated by request-id with
per-request timeout tasks. A connection health probe uses a 3-second
`query-device-info` round trip — dead TCP connections fail fast, so the full
timeout is rarely paid.
([RockYou/Network/RokuWebSocketClient.swift](RockYou/Network/RokuWebSocketClient.swift))

**Command routing.** A higher-level client owns a WebSocket pool keyed by IP
with single-flight connects, and routes commands through per-device FIFO
"silos" so ordering is preserved. Power-on requests gate on Wake-on-LAN +
device wake; other keys deliberately do not wait, preserving user-perceived
ordering. ([RockYou/Network/RokuECPClient.swift](RockYou/Network/RokuECPClient.swift))

**Household sync.** TV pairings and per-device app usage (MRU ordering) sync
across the household via a single CloudKit share. MRU merges are newest-wins —
an entry never moves backward in time — which makes ordering convergence
correct without suppressing any observer. Writes are debounced (1.5 s) and
throttled (15 s per device) behind a transition guard, so idle polling writes
nothing. ([RockYou/Devices/CloudKitHouseholdStore.swift](RockYou/Devices/CloudKitHouseholdStore.swift))

**Watch.** watchOS denies low-level networking to third-party apps (SSDP
multicast and raw WebSockets both fail NECP policy; see Apple TN3135), so the
watch app is a pure proxy: all discovery, sockets, and state live on the
phone, and the watch talks WatchConnectivity — including hash-diffed app icon
transfer sized for the watch. ([RockYou Watch App/ConnectivityManager.swift](RockYou%20Watch%20App/ConnectivityManager.swift))

## Engineering notes

Non-obvious decisions, each with the file or doc that motivates it:

- **The ECP-2 auth key is not in this repository — by design.** The app fetches
  it at runtime from an app-scoped CloudKit record and caches it locally
  ([RockYou/Network/RokuAuthKeyStore.swift](RockYou/Network/RokuAuthKeyStore.swift)).
  Builds provisioned for a different CloudKit container must supply their own
  copy of the key in their own container.
- **ECP-1 is compiled out, not just unused.** HTTP fallback helpers require an
  explicit `-DROCKYOU_ENABLE_ECP1_FALLBACK` flag, so Limited-Mode 403s cannot
  silently reappear as a degraded path
  ([RockYou/Network/RokuECPClient.swift](RockYou/Network/RokuECPClient.swift)).
- **Streamer↔TV pairing** routes volume/power keys to a paired Roku TV while
  navigation goes to the streaming stick — streaming devices cannot control TV
  volume or power themselves
  ([Resources/Docs/Protocol.md](Resources/Docs/Protocol.md)).
- **Protocol quirks are documented, not patched around silently**: which
  advertised events are accepted but never emitted, `param-mute` vs
  `param-muted`, why active-app tracking rides `media-player-state-changed`,
  and why a 5-second poll backs up apps (Netflix) that omit state events
  ([Resources/Docs/Protocol.md](Resources/Docs/Protocol.md)).
- **CloudKit schema-version gating**: if cloud data was written by a newer app
  version, this build blocks CloudKit access entirely rather than risk
  corrupting it; shared-zone migration is deliberately deferred
  ([RockYou/Devices/CloudKitHouseholdStore.swift](RockYou/Devices/CloudKitHouseholdStore.swift)).
- **Platform splits use file naming, not `#if` sprawl**: one type name,
  `+iOS`/`+macOS`/`+watchOS`/`+nonWatch` filename suffixes, build-time
  inclusion per target ([docs/DESIGN_GUIDE.md](docs/DESIGN_GUIDE.md)).
- **Release builds compile logging to nothing**: `@autoclosure` messages with
  inlinable no-op bodies outside DEBUG, so verbose protocol tracing has zero
  release cost ([Shared/Log.swift](Shared/Log.swift)).
- **The GPU iris/dome effect is developed CPU-first**: a reference CPU mask
  implementation validates the math before it is frozen and ported to Metal
  geometry modifiers; the design is written up in eight steps in
  [docs/Dome/](docs/Dome/), and shader algorithms are selected at compile time
  via a scaffold macro rather than runtime dispatch
  ([RockYou/UI/Shaders/FragmentShaderScaffold.h](RockYou/UI/Shaders/FragmentShaderScaffold.h)).
- **Debug-harness UI is generated from KeyPaths**: experimental engines declare
  properties plus a one-line config entry, and the panel UI derives from that
  ([Shared/PropertyConfig.swift](Shared/PropertyConfig.swift)).

## Building

Requirements: Xcode targeting iOS 18 / macOS 15 / watchOS 10, and an Apple
Developer team (the app uses CloudKit, push, App Groups, and the multicast
entitlement).

1. Open `RockYou.xcodeproj` and set your own development team on the three app
   targets.
2. CloudKit: the container id in
   [RockYou/CloudKitConfig.swift](RockYou/CloudKitConfig.swift) and the
   entitlements files must point at a container your team owns. Create the
   record types in your container (they bootstrap from
   [RockYou/Devices/CloudKitHouseholdStore.swift](RockYou/Devices/CloudKitHouseholdStore.swift)
   on first run in the development environment), and add an `AppConfig` record
   named `roku-ecp2-auth-key` whose `value` field holds the ECP-2 key — this
   repository does not ship it.
3. Local network: on first run, grant the local-network prompt. SSDP requires
   the `com.apple.developer.networking.multicast` entitlement on physical iOS
   devices.

`buildrun.yaml` configures an optional CLI build wrapper used during
development; plain Xcode builds work without it. CI runs on Xcode Cloud —
[ci_scripts/asc_next_build_number.swift](ci_scripts/asc_next_build_number.swift)
computes the next build number from the App Store Connect API (ES256 JWT via
CryptoKit, paginated build query) instead of hand-managing it.

## Using it

- Devices on the same network appear automatically; tap one to control it.
- Pair a streaming stick with a Roku TV to get volume/power on the TV while
  navigating the stick.
- Invite household members to the CloudKit share so pairings and app ordering
  follow everyone's devices.
- The watch app mirrors devices and apps paired through the phone; widgets and
  complications launch straight into a chosen device.

## Support matrix

| Area | Status |
| --- | --- |
| Roku TVs and streaming players (ECP-2) | Implemented; the protocol surface marked `Unverified*` in code is best-guess and untested |
| Non-Roku TVs (Samsung, LG, Sony, Vizio, Android/Fire TV) | Research notes only ([Resources/Docs/TV-Protocols.md](Resources/Docs/TV-Protocols.md), [Resources/Docs/OtherTVPlans.md](Resources/Docs/OtherTVPlans.md)); not implemented |
| Wake-on-LAN | iOS/macOS only; watchOS cannot send it |
| watchOS direct device control | Not possible (OS networking policy); watch proxies through the phone |
| HDMI-CEC power control | Deliberately deferred — needs a hardware bridge |
| CloudKit schema migration | Placeholder only; mismatched schema blocks sync rather than migrating |

Known gaps are tracked honestly in [docs/WORK_REMAINING.md](docs/WORK_REMAINING.md).

## Architecture

| Path | Contents |
| --- | --- |
| `RockYou/` | iOS/macOS app (one target, not Catalyst): UI, network clients, CloudKit household store, protocol explorer, debug harnesses |
| `RockYou Watch App/`, `RockYou Watch Widgets/` | watchOS app and WidgetKit complications |
| `Shared/` | Cross-target code: device state, app cache, WatchConnectivity wire types, logging, Wake-on-LAN |
| `Resources/Docs/` | Protocol reference (MPL-2.0): ECP-1/ECP-2, other-TV research |
| `docs/` | Developer and design guides; the iris/dome GPU effect design series |
| `ci_scripts/` | Xcode Cloud hooks |

State flows through two `@Observable` singletons — `DeviceStateManager` (live
device state keyed by stable device id, not IP) and `AppCacheManager`
(installed apps, icons, MRU) — with token-based change handlers for
non-SwiftUI observers such as the watch bridge and CloudKit MRU recording.
Unit tests target the extracted state machines (gesture sweep/press,
touch-target picking, complication target selection) rather than UI
automation.

## License

Split-licensed; see [LICENSE](LICENSE). The reverse-engineered protocol layer
(the ECP-2 client, discovery, parsing, and the protocol reference docs) is
MPL-2.0 so it can be reused with improvements flowing back. The application
itself is PolyForm Perimeter 1.0.1: source-available, no competing
repackaging. Copyright (c) 2026 Delphar Se7en.
