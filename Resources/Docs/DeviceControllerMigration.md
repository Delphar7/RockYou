## DeviceController (“whole device”) migration plan

### Goal
Unify iOS + macOS + watchOS around a single “whole device” abstraction that can represent:
- A single TV (power/volume only or full Roku TV)
- A single streamer (no power/volume unless the device supports it, e.g. Streambar)
- A paired TV + streamer where roles are split (typically power/volume on TV, everything else on streamer)

Key outcome: the Watch never needs to reason about “paired endpoints”; it targets a single controller and the phone routes commands correctly.

---

### Current state (as of this session)
- **Wire-safe model exists**: `Shared/Devices/DeviceControllerDescriptor.swift`
  - **ID scheme**:
    - TV: `tvId`
    - Streamer: `streamerId`
    - Pair: `tvId:streamerId`
  - **Minimal routing**:
    - `controlEndpointId` (nav/apps/transport/etc)
    - `hardwareEndpointId` (power/volume if present)
- **Controller builder exists (iOS/macOS)**: `RockYou/Devices/DeviceControllerBuilder.swift`
  - Builds `[DeviceControllerDescriptor]` from discovery endpoints + `PairingStore.pairings`
- **WatchConnectivity payloads carry controllers (back-compat optional)**:
  - `WCHandshakeReply.controllers?`
  - `WCDeviceListEvent.controllers?`
  - `WatchSurfaceSnapshot.controllers?`
- **Watch UI selection uses controllers**
  - Stores `selectedControllerId` and routes actions via hardware/control endpoint ownership.

This already fixes the “paired TV/streamer shows up twice on watch” symptom.

---

### Target architecture (end state)

#### 1) Shared (Codable) descriptor layer
Keep a small, stable, Codable descriptor that can cross the wire and be cached:
- `DeviceControllerDescriptor` (value type)
- Optional expansion later: richer role/capability map (instead of only control vs hardware)

#### 2) Runtime controller layer (iOS/macOS)
Introduce a runtime protocol used by the app (not Codable):
- `protocol DeviceController`
  - `var descriptor: DeviceControllerDescriptor { get }`
  - `func endpointId(for action: RemoteAction) -> String?` (or `for role`)
  - `func send(action:)` / `launchApp(appId:)` / etc (optional convenience)

Implementations:
- `SingleDeviceController` (one endpoint owns all supported roles)
- `PairedDeviceController` (role ownership split across endpoints)

#### 3) Watch proxy layer
Watch should operate on descriptors and send “controller-targeted” requests:
- Watch keeps `selectedControllerId`
- Watch sends requests including `controllerId` (and possibly role/action)
- Phone resolves controller → endpoint → performs network call

---

### Migration phases

#### Phase A — Stabilize the descriptor list everywhere
- Ensure iOS/mac UI can build and display controller list (same logic as watch).
- Decide ordering and display naming rules.
- Ensure pairing changes produce new IDs (`tvId:streamerId`) and invalidate old selections cleanly.

Deliverable:
- A single “Select Device” list conceptually showing controllers (even if UI stays mostly unchanged initially).

#### Phase B — Convert selection persistence on iOS/mac to controller IDs
- Add `selectedControllerId` persistence (new key), keep legacy keys for migration:
  - If legacy selection is an endpoint ID, map it to the best controller:
    - If it participates in a pairing, prefer that paired controller
    - Else map to the single controller
- Keep old paths temporarily, but make controller selection the new source of truth.

Deliverable:
- iOS/mac and watch now agree on “what is selected”.

#### Phase C — Controller-targeted WatchConnectivity requests
- Extend `WCRequest` to include controller-targeted variants (keep legacy for old watch builds):
  - e.g. `keypress(controllerId: String, key: String)` and `launchApp(controllerId: String, appId: String)`
- Phone:
  - Resolve controllerId → descriptor → endpointId (hardware/control) → send
  - Continue accepting legacy `deviceId/deviceIdx` during rollout
- Watch:
  - Prefer controller requests once controller list is present

Deliverable:
- Watch no longer needs endpoint ids for routing; it can use controller ids only.

#### Phase D — Replace in-app routing with controllers
- iOS/mac:
  - Replace `RemoteControlSelection` “selectedDeviceId” derivation with controller-based derivation
  - Move “pair routing” logic into controller implementation
- Ensure MRU / device state updates are keyed consistently (endpoint vs controller where appropriate).

Deliverable:
- One routing model everywhere: “controller chooses endpoint”.

#### Phase E — Cleanup (remove old code)
- Remove legacy selection keys and mapping once stable.
- Remove legacy WC request variants once minimum supported watch build is controller-aware.
- Remove duplicated routing code in `RemoteControlSelection`, `iOSDeviceStateProvider`, and any watch-specific endpoint hacks.

Deliverable:
- Minimal duplication; pairing logic is centralized.

---

### Notes / constraints
- This repo uses file-system-synchronized groups plus `EXCLUDED_SOURCE_FILE_NAMES[...]` patterns; platform suffixes like `+iOS` matter only insofar as those patterns match them.
- Avoid large-scale rename churn during migration: prefer typealiases or adapter structs/classes where needed.
- Prefer deleting old paths once the new controller selection/requests are proven (Joe’s “no dead code” rule).
