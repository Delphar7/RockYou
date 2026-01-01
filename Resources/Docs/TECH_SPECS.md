# RockYou — Technical Specs

This doc consolidates protocol knowledge, platform constraints, and “we already learned this the hard way” details.

## Roku ECP overview

Roku devices expose local control primarily on port **8060**:

- **ECP-1 (HTTP)**: unauthenticated HTTP endpoints for keypresses + queries (can be blocked by “Limited Mode”)
- **ECP-2 (WebSocket)**: authenticated WebSocket protocol (bypasses “Limited Mode”, supports events)

Reference: [Roku External Control API](https://developer.roku.com/docs/developer-program/dev-tools/external-control-api.md)

For deeper notes and examples (including ECP-2 message formats), see `Protocol.md`.

### ECP-1 (HTTP)

- Send keypress:
  - `POST http://{ip}:8060/keypress/{key}`
- Common queries:
  - `GET http://{ip}:8060/query/device-info`
  - `GET http://{ip}:8060/query/apps`
  - `GET http://{ip}:8060/query/active-app`
  - `GET http://{ip}:8060/query/media-player`
  - `GET http://{ip}:8060/query/icon/{app-id}`

“Limited Mode” typically manifests as **HTTP 403** for `/keypress/*`.

### ECP-2 (WebSocket)

- URL: `ws://{ip}:8060/ecp-session`
- Subprotocol: `Sec-WebSocket-Protocol: ecp-2`
- Connect → receive challenge → authenticate → subscribe to events

#### Quirks / gotchas

- Treat **202 Accepted** as success for some requests.
- `active-app-changed` is often accepted as a subscription but **not actually emitted**; `media-player-state-changed` with `param-channel-id` is the more reliable “active app” signal.

## watchOS networking constraints (important)

watchOS restricts low-level networking APIs unless the app is actively streaming audio (documented Apple policy, not a bug).

- **Works**: `URLSession.dataTask` (HTTP/HTTPS)
- **Generally blocked**: multicast discovery (`NWConnectionGroup`/`NWMulticastGroup`), and low-level socket-style APIs unless in an audio-streaming scenario

### Support matrix (what “blocked” actually means)

“Blocked” typically surfaces as:

```text
Path was denied by NECP policy
```

To use low-level networking APIs on watchOS, the system expects a real streaming-audio scenario (not just “I opened a socket”):

- Background Audio capability enabled
- Active `AVAudioSession`
- Requests marked `networkServiceType = .avStreaming`
- App is actually streaming audio

Practical API notes:

- `URLSession.dataTask` (HTTP/HTTPS): ✅ works normally
- `URLSession.webSocketTask` / `NWConnection` WebSocket: ⚠️ typically blocked unless streaming audio
- SSDP discovery (multicast): ⚠️ blocked unless streaming audio

Practical impact for RockYou:

- Watch can do HTTP ECP-1 once it knows the IP, but generally cannot do:
  - SSDP discovery
  - ECP-2 WebSocket
- Therefore, watch relies on iPhone for:
  - discovery
  - stable ECP-2 connectivity
  - anything requiring low-level networking (and for future WoL)

Reference: Apple TN3135 “Low-level networking on watchOS”.

### Implication for TV discovery & pairing

If we add “Other TV” control on watchOS, discovery must be mediated by iPhone (or manual IP entry), because the Watch cannot reliably do multicast discovery or long-lived sockets.

## Other TV protocols (future expansion notes)

If RockYou expands beyond Roku, likely high-value targets:

For detailed research notes (Samsung/LG/Sony/etc.), see `TV-Protocols.md`.

- Samsung (Tizen): WebSocket remote API (power off works; power on often requires WoL)
- LG (webOS): WebSocket SSAP
- Vizio: HTTPS REST API

Universal constraint:

- **Power ON** frequently requires **Wake-on-LAN** even when power OFF is supported.
