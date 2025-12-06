# RockYou — Work Remaining

This is the living “what’s left” list. Anything completed should be removed or moved into history elsewhere.

## Core architecture

### Device/pair sessions owning WebSockets

Goal: make it structurally impossible to accidentally create multiple WebSockets per device.

Desired shape:

- `DeviceSession` (actor) owns:
  - one `RokuWebSocketClient` per device
  - connect/reconnect/backoff
  - device-level commands (keypress, launch, queries, icon fetch)
- `SiloSession` (actor) owns:
  - TV-only: one `DeviceSession`
  - TV + streamer: two `DeviceSession`s, treated as one ordered “unit”
  - ordering / gating policies (wake vs “don’t wake” commands)

Enforcement idea:

- hide construction so `RokuWebSocketClient(...)` can only occur inside sessions
- everything else talks to `DeviceSession` / `SiloSession` APIs

## UX / feature work

- **AppStrip**: highlight current app in the strip (glow/border/shimmer)
- **Media time sync**: query media playing state to keep current time in sync
- **iPhone panels**: slidable panels (postponed)

## Shipping

- TestFlight external “Beta App Review” approval (when ready)

## Technical debt

- remove or gate verbose debug logging before release
- add better user-facing error handling for connection failures

## Future ideas (parking lot)

- “Turn off all On TVs” one-tap control
- Wake-on-LAN fallback for truly-off devices (requires MAC address persistence)
- Siri Shortcuts / automation
- widget(s)
