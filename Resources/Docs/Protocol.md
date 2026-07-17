# Roku External Control Protocol (ECP) Documentation

This document describes the Roku External Control Protocol, including both the HTTP-based ECP-1 and the authenticated WebSocket-based ECP-2 protocols.

---

## Table of Contents

1. [Overview](#overview)
2. [Discovery (SSDP)](#discovery-ssdp)
3. [HTTP ECP (ECP-1)](#http-ecp-ecp-1)
4. [WebSocket ECP (ECP-2)](#websocket-ecp-ecp-2)
5. [Authentication](#authentication)
6. [Commands](#commands)
7. [Events & Notifications](#events--notifications)
8. [Device Info Fields](#device-info-fields)
9. [Known Issues & Quirks](#known-issues--quirks)

---

## Overview

Roku devices expose a local network API on **port 8060** for remote control. There are two protocols:

| Protocol | Transport | Authentication | Notes |
|----------|-----------|----------------|-------|
| **ECP-1** | HTTP | None (or "Limited Mode") | Simple POST requests for keypresses, GET for queries |
| **ECP-2** | WebSocket | Challenge-response | Bypasses "Limited Mode", supports real-time events |

### Ports

- **8060** - ECP HTTP and WebSocket (ws://)
- **8443** - Secure WebSocket (wss://) - rarely used

---

## Discovery (SSDP)

Roku devices advertise themselves via SSDP (Simple Service Discovery Protocol) on multicast address `239.255.255.250:1900`.

### M-SEARCH Request

```http
M-SEARCH * HTTP/1.1
HOST: 239.255.255.250:1900
MAN: "ssdp:discover"
MX: 3
ST: roku:ecp
```

### Response

```http
HTTP/1.1 200 OK
Cache-Control: max-age=3600
ST: roku:ecp
USN: uuid:roku:ecp:SERIAL_NUMBER
Ext:
Server: Roku/VERSION UPnP/1.0 Roku/VERSION
LOCATION: http://192.168.1.100:8060/
```

The `LOCATION` header provides the ECP base URL for the device.

### Device Type Detection

Query `/query/device-info` and check the `is-tv` field:
- `is-tv: true` → Roku TV (has built-in display, HDMI inputs)
- `is-tv: false` → Streaming device (Stick, Ultra, Express, etc.)

---

## HTTP ECP (ECP-1)

### Query Endpoints (GET)

| Endpoint | Description |
|----------|-------------|
| `/query/device-info` | Device metadata (model, serial, name, capabilities) |
| `/query/apps` | List of installed channels/apps |
| `/query/active-app` | Currently running application |
| `/query/media-player` | Media playback state (position, duration, etc.) |
| `/query/icon/{app-id}` | App icon image (PNG) |
| `/query/tv-channels` | Live TV channels (Roku TVs only) |
| `/query/tv-active-channel` | Current live TV channel |

### Command Endpoints (POST)

| Endpoint | Description |
|----------|-------------|
| `/keypress/{key}` | Send a single keypress |
| `/keydown/{key}` | Key down (for held keys) |
| `/keyup/{key}` | Key up |
| `/launch/{app-id}` | Launch an app/channel |
| `/launch/{app-id}?contentId={id}` | Launch app with deep link |
| `/input?{params}` | Send input parameters |
| `/search/browse?keyword={term}` | Search across apps |

### Example: Send Keypress

```bash
curl -X POST http://192.168.1.100:8060/keypress/Home
```

### "Limited Mode" (HTTP 403)

By default, some Roku devices restrict network control. When in "Limited Mode":
- HTTP POST to `/keypress/*` returns **403 Forbidden**
- User must enable in: **Settings → System → Advanced system settings → Control by mobile apps → Network access → Default or Permissive**

The ECP-2 WebSocket protocol bypasses this restriction via authentication.

---

## WebSocket ECP (ECP-2)

### Connection

1. Connect to `ws://{ip}:8060/ecp-session`
2. Set WebSocket subprotocol: `ecp-2`
3. Server sends authentication challenge
4. Client responds with computed auth response
5. Server confirms authentication
6. Client subscribes to events
7. Connection ready for commands

### URL

```
ws://192.168.1.100:8060/ecp-session
```

### Subprotocol

The WebSocket handshake must include:

```
Sec-WebSocket-Protocol: ecp-2
```

---

## Authentication

### Challenge Message (Server → Client)

```json
{
  "notify": "authenticate",
  "param-challenge": "A1B2C3D4E5F6...",
  "timestamp": "123456.789"
}
```

### Response Computation

The key value is not stored in this repository. The app fetches it at runtime from an
app-scoped CloudKit record (`RokuAuthKeyStore`); builds provisioned for a different CloudKit
container must supply their own copy of the key there.

```
KEY = <32 hex chars in UUID format, fetched at runtime>

function charTransform(char, shift=9):
    if char is hex digit (0-9, A-F):
        value = hexToInt(char)
        result = (15 - value + shift) & 15
        return intToHex(result)
    return char

TRANSFORMED_KEY = KEY.map(c => charTransform(c, 9))
SEED = challenge + TRANSFORMED_KEY
DIGEST = SHA1(SEED)
RESPONSE = base64(DIGEST)
```

### Authentication Request (Client → Server)

```json
{
  "request": "authenticate",
  "request-id": "1",
  "param-response": "<base64-sha1-response>",
  "param-client-friendly-name": "RockYou Remote",
  "param-has-microphone": "false",
  "param-microphone-sample-rates": "16000"
}
```

### Authentication Response (Server → Client)

**Success:**
```json
{
  "response": "authenticate",
  "response-id": "1",
  "status": "200",
  "status-msg": "OK"
}
```

**Failure:**
```json
{
  "response": "authenticate",
  "response-id": "1",
  "status": "401",
  "status-msg": "Unauthorized"
}
```

---

## Commands

All commands follow a request/response pattern with `request-id` for correlation.

### Keypress

**Request:**
```json
{
  "request": "key-press",
  "request-id": "2",
  "param-key": "Up"
}
```

**Response:**
```json
{
  "response": "key-press",
  "response-id": "2",
  "status": "200",
  "status-msg": "OK"
}
```

### Available Keys

| Category | Keys |
|----------|------|
| **Navigation** | `Up`, `Down`, `Left`, `Right`, `Select`, `Back`, `Home` |
| **Playback** | `Play`, `Pause`, `Rev`, `Fwd`, `InstantReplay` |
| **Volume** | `VolumeUp`, `VolumeDown`, `VolumeMute` |
| **Power** | `Power`, `PowerOn`, `PowerOff` |
| **Other** | `Info` (options/*), `Search`, `FindRemote`, `Backspace`, `Enter` |
| **Input** | `InputTuner`, `InputHDMI1`, `InputHDMI2`, `InputHDMI3`, `InputHDMI4`, `InputAV1` |
| **Literal** | `Lit_{character}` - Type a character (URL-encoded for special chars) |

### Key Held (for repeat)

```json
{
  "request": "key-down",
  "request-id": "3",
  "param-key": "VolumeUp"
}
```

```json
{
  "request": "key-up",
  "request-id": "4",
  "param-key": "VolumeUp"
}
```

### Launch App

```json
{
  "request": "launch",
  "request-id": "5",
  "param-app-id": "12345"
}
```

### Launch with Deep Link

```json
{
  "request": "launch",
  "request-id": "6",
  "param-app-id": "12345",
  "param-content-id": "movie/abc123"
}
```

---

## Events & Notifications

### Subscribe to Events

**Request:**
```json
{
  "request": "request-events",
  "request-id": "2",
  "param-events": "+power-mode-changed,+volume-changed,+media-player-state-changed,+active-app-changed"
}
```

**Response:**
```json
{
  "response": "request-events",
  "response-id": "2",
  "status": "200"
}
```

**Status Codes:**
- `200` - OK, subscription successful
- `202` - Accepted (busy but will process) - subscription accepted, may be processing

**Invalid Event Handling:**
- Roku accepts subscriptions with invalid/non-existent event names (returns 200/202)
- Invalid events are silently ignored - no notifications sent for them
- Valid events in the same subscription request still work normally
- This allows graceful degradation if an event type doesn't exist on a particular device/firmware

**Event Reliability Notes:**
- `active-app-changed`: **Not sent by Roku devices** - Despite being documented, this notification is never sent. Use `media-player-state-changed` with `param-channel-id` as the reliable source for active app changes.
- `media-player-state-changed`: **Reliably sent** by most apps. Includes `param-channel-id` (app ID) and `param-channel-title` (app name) which can be used to track active app changes.
- `screensaver-started/stopped`: **Not sent by Roku devices** - Despite being documented and subscriptions being accepted, these notifications are never sent. Tested with screensaver activation; no notifications received.

### Available Events

| Event | Description |
|-------|-------------|
| `power-mode-changed` | Device power state changed |
| `volume-changed` | Volume level or mute state changed |
| `media-player-state-changed` | Media playback started/stopped/paused |
| `active-app-changed` | Active application changed (not sent by Roku - use `media-player-state-changed` with `param-channel-id` instead) |
| `screensaver-started` | Screensaver activated (not sent by Roku - subscriptions accepted but notifications never sent) |
| `screensaver-stopped` | Screensaver deactivated (not sent by Roku - subscriptions accepted but notifications never sent) |

### Event Notifications (Server → Client)

**Power Mode Changed:**
```json
{
  "notify": "power-mode-changed",
  "param-power-mode": "power-on",
  "timestamp": "123456.789"
}
```

Power modes:
- `power-on` - Fully on, screen active
- `ready` - Low-power standby (screen off, listening for wake)
- `power-off` - True off (may be unreachable)
- `display-off` - Display forced off but device active
- `Suspend` - Suspended state (observed on some devices)

**Volume Changed:**
```json
{
  "notify": "volume-changed",
  "param-volume": "18",
  "param-mute": "false",
  "param-audio-destination": "arc",
  "timestamp": "123456.789"
}
```

Audio destinations:
- `speaker` - Built-in TV speakers
- `arc` - HDMI ARC/eARC to soundbar/receiver
- `headphone` - Headphone jack
- `wireless` - Bluetooth/wireless speakers

**Media Player State Changed:**
```json
{
  "notify": "media-player-state-changed",
  "param-channel-id": "2285",
  "param-channel-title": "Hulu",
  "param-media-player-state": "play",
  "param-media-player-position": "10757116 ms",
  "param-media-player-duration": "10787080 ms",
  "timestamp": "123456.789"
}
```

Media states:
- `open` - App opened/starting
- `startup` - Loading content
- `buffer` - Buffering
- `play` - Playing
- `pause` - Paused
- `stop` - Stopped
- `close` - Closed

**Active App Changed:**
```json
{
  "notify": "active-app-changed",
  "param-active-app-id": "2285",
  "param-active-app-name": "Hulu",
  "timestamp": "123456.789"
}
```

### Unsubscribe from Events

```json
{
  "request": "request-events",
  "request-id": "10",
  "param-events": "-power-mode-changed,-volume-changed"
}
```

---

## Device Info Fields

From `/query/device-info`:

| Field | Description | Example |
|-------|-------------|---------|
| `udn` | Unique Device Name (UUID) | `29380000-1234-1234-...` |
| `serial-number` | Device serial | `YN00AB123456` |
| `device-id` | Alternate ID | `A1B2C3D4E5F6` |
| `friendly-device-name` | User-set name | `Living Room TV` |
| `model-name` | Model | `Roku Ultra` |
| `model-number` | Model number | `4670X` |
| `vendor-name` | Manufacturer | `Roku` or `TCL`, `Hisense`, etc. |
| `is-tv` | Is this a TV? | `true` / `false` |
| `is-stick` | Is this a Stick? | `true` / `false` |
| `power-mode` | Current power state | `power-on`, `ready`, etc. |
| `supports-audio-guide` | Accessibility feature | `true` / `false` |
| `supports-find-remote` | Can beep remote | `true` / `false` |
| `supports-private-listening` | Headphone streaming | `true` / `false` |
| `supports-suspend` | Supports suspend mode | `true` / `false` |
| `supports-wake-on-wlan` | Wake-on-LAN support | `true` / `false` |
| `has-play-on-roku` | Screen mirroring | `true` / `false` |
| `network-type` | Connection type | `wifi` / `ethernet` |
| `wifi-mac` | WiFi MAC address | `aa:bb:cc:dd:ee:ff` |
| `ethernet-mac` | Ethernet MAC address | `aa:bb:cc:dd:ee:ff` |
| `software-version` | OS version | `11.5.0` |
| `software-build` | Build number | `4242` |

---

## Known Issues & Quirks

### Status Code 202

Some commands return `202 Accepted` instead of `200 OK`. This indicates the device acknowledged the command but is busy processing. Treat `202` as success.

### Power Mode "Suspend" vs "ready"

Some devices report `Suspend` instead of `ready` for low-power standby. The Roku streaming sticks (Ultra, etc.) connected via USB may show different power modes than TVs.

### Mute Field Naming

The mute field is inconsistently named:
- `param-mute` in volume-changed notifications
- `param-muted` in some older firmware

### Volume/Power on Streaming Devices

Streaming devices (Stick, Ultra, Express) **cannot** control TV volume/power via ECP when connected via HDMI-CEC. The ECP commands are local to the Roku only.

**Workaround:** RockYou implements "pairing" where volume/power commands route to a Roku TV while navigation commands go to the streamer.

### Discovery on watchOS

watchOS has restricted networking. Multicast discovery via `NWConnectionGroup` may not work. Workarounds:
- Relay through paired iPhone via WatchConnectivity
- Sync discovered devices from phone
- Manual IP entry

### WebSocket Path Required

When using `NWConnection` for WebSocket, you must include the path:
```swift
NWConnection(to: .url(URL(string: "ws://ip:8060/ecp-session")!), using: parameters)
```

Simple host:port connections won't work for ECP-2.

---

## Response Status Codes

| Code | Meaning |
|------|---------|
| `200` | OK - Success |
| `202` | Accepted - Command queued (treat as success) |
| `400` | Bad Request - Malformed command |
| `401` | Unauthorized - Authentication failed |
| `403` | Forbidden - Limited mode (HTTP only) |
| `404` | Not Found - Unknown command/endpoint |
| `500` | Server Error - Device error |

---

## Example Session

```
[Client connects to ws://192.168.1.100:8060/ecp-session]

← {"notify":"authenticate","param-challenge":"ABC123...","timestamp":"123.456"}
→ {"request":"authenticate","request-id":"1","param-response":"xyz==","param-client-friendly-name":"RockYou"}
← {"response":"authenticate","response-id":"1","status":"200","status-msg":"OK"}

→ {"request":"request-events","request-id":"2","param-events":"+power-mode-changed,+volume-changed"}
← {"response":"request-events","response-id":"2","status":"200"}

→ {"request":"key-press","request-id":"3","param-key":"Home"}
← {"response":"key-press","response-id":"3","status":"200","status-msg":"OK"}

← {"notify":"volume-changed","param-volume":"15","param-mute":"false","timestamp":"124.567"}
← {"notify":"power-mode-changed","param-power-mode":"ready","timestamp":"125.678"}
```

---

## References

- [Roku Developer Documentation - ECP](https://developer.roku.com/docs/developer-program/dev-tools/external-control-api.md)
- RockYou implementation: `RokuWebSocketClient.swift`, `RokuECPClient.swift`

---

*Last updated: December 6, 2025*
