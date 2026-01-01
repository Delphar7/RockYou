# Other TV Support — Plan (Power / Volume / Mute)

This doc captures how RockYou can expand beyond Roku TVs and support **TV power/volume** for common non‑Roku TV ecosystems, while keeping the architecture clean and testable.

## Priority TV models / brands

Prioritize by (a) install base, (b) protocol maturity, (c) ability to validate behavior without owning the hardware.

- **LG webOS (2014+)**
  - **Protocol**: WebSocket SSAP (“second screen”).
  - **Why first**: protocol/message shapes are well understood, multiple mature open-source clients exist for cross-validation.
  - **Power ON**: usually requires **Wake-on-LAN** + known MAC.

- **Samsung (Tizen era smart TVs, ~2016+)**
  - **Protocol**: WebSocket remote API (`samsung.remote.control` JSON).
  - **Why second**: huge install base + many working open-source clients.
  - **Power ON**: commonly WoL; often needs pairing acceptance/token.

- **Sony Bravia (Android TV variants)**
  - **Protocol**: IRCC (SOAP POST) + REST endpoints with PSK/PIN depending on model/settings.
  - **Why third**: feasible surface area for volume/mute/power, but more model/settings variance.

Defer initially:

- **HDMI‑CEC**: powerful but typically needs a hardware bridge (not phone→TV over LAN).
- **“Long tail” brands** (Hisense/VIDAA variants, etc.): higher variance; better once we have the discovery wizard + crowd-sourced probe data.

## General cycle for adding support (per brand)

The loop for each brand should be consistent:

1. **Spec & capabilities**
   - Define the minimal command set: `volumeUp`, `volumeDown`, `muteToggle` (or `setMute(bool)`), `powerOff` (and `powerOn` if feasible).
   - Decide whether power is **toggle** vs **discrete** (`powerOn`/`powerOff`) and treat toggle as higher-risk UX.

2. **Discovery heuristics**
   - Implement discovery of “candidates” (SSDP/mDNS + port hints) that yields:
     - IP address
     - make/model strings (best-effort)
     - unique id / uuid (if advertised)
     - MAC address (if obtainable; otherwise “unknown” until paired)

3. **Pairing/auth**
   - Implement a pairing flow and persistent credential storage:
     - LG: client key
     - Samsung: token
     - Sony: PSK or pairing code / token (varies)
   - Pairing is **user-driven** (explicit “Pair” tap) and should never be attempted silently.

4. **Command implementation**
   - Implement TV-control commands behind a small interface (see below).
   - Add robust retry/backoff; classify errors (network unreachable vs auth required vs command unsupported).

5. **Validation (without owning hardware)**
   - Cross-check request/response shapes against known open-source clients (treat them as an “oracle”).
   - Build a small **mock server** for each brand protocol and add conformance tests for:
     - auth gating (commands fail until paired)
     - expected payload formats
     - reconnect + credential persistence

6. **Ship guarded**
   - Gate behind a feature flag / “Other TVs (beta)” section until we have enough field data.
   - Add a “report / export diagnostics” capability so real users can help validate.

## General Wake-on-LAN (WoL) support (also useful for Roku)

WoL is a cross-cutting feature. Even Roku ecosystems can benefit (e.g. waking a TV/receiver in a paired setup).

- **What WoL needs**
  - MAC address
  - broadcast address / subnet info (or fall back to common broadcast patterns)
  - UDP packet sender (magic packet)

- **Capability modeling**
  - Treat “supports WoL” as a tri-state: **yes / no / unknown**.
  - In practice: if we have a MAC and support is **unknown**, a wake attempt is still reasonable (it’s harmless and has no ack).

- **Constraints**
  - WoL works only if enabled on the TV and supported by hardware/firmware.
  - On iOS, background execution limits mean “wake then immediately control” should be user-initiated (foreground).

- **Design**
  - Treat WoL as an **optional preflight step** for “Power On”.
  - Record whether WoL succeeded recently (avoid spamming the LAN).

## Discovery interface (source of truth for TVs)

We want multiple “sources of truth” (manual entry, discovery, cloud/shared household) but one shared model.

Minimum discovery result fields:

- **IP address** (required)
- **Make/brand guess** (optional, best-effort)
- **Model / friendly name** (optional)
- **MAC address** (optional but strongly desired for WoL)

Suggested model split:

- **TVIdentity**
  - stable id (derived from uuid/mac/ip+fingerprint)
  - display name
  - brand/model (best-effort)
  - last known IP
  - mac (optional)

- **TVControlEndpoint**
  - protocol type (LG SSAP / Samsung WS / Sony IRCC / Roku TV control / etc.)
  - auth state + stored credential reference
  - capability flags (supports discrete power? supports setMute?)

## Guided “discover your TV” wizard (future, but start shaping now)

Goal: a user can add support for their TV with minimal confusion, and can optionally export a diagnostic bundle if unsupported.

High-level flow:

1. **Select brand (or “Not sure”)**
   - If “Not sure”: run discovery and show candidates with a confidence score.

2. **Pick a device**
   - Show IP/name/model if known.
   - Explain what will happen next (pairing prompt may appear on TV).

3. **Pair**
   - Present brand-specific instructions:
     - enable “remote apps” / “mobile TV on” settings if required
     - accept prompt / enter PIN when applicable
   - Persist credentials securely.

4. **Test**
   - Provide explicit buttons:
     - “Test Volume Up”
     - “Test Mute”
     - “Test Power Off”
     - “Test Power On” (with WoL preflight if we have MAC)
   - Capture results in a structured log.

5. **If unsupported**
   - Offer “Export diagnostics” (Share Sheet) containing:
     - anonymized discovery info
     - protocol handshake results (redacted)
     - app version + platform

Key UX rule: never send disruptive commands automatically. All tests are explicit taps.

## Anything else (pragmatic notes)

- **Store LAN scanning**: often blocked by client isolation; plan assumes home LAN / user-assisted testing.
- **Security posture**: store credentials in Keychain; export bundles must redact tokens/keys by default.
- **Non-duplication**: keep one “TV control” interface and plug brand implementations behind it, rather than sprinkling brand logic throughout UI flows.
