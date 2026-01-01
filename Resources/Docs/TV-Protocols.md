# TV Control Protocols Research

Research into TCP/IP protocols for controlling various TV brands, focused on **power** and **volume** control.

Prioritized by estimated global TV market share (2024):
1. Samsung (~20%)
2. LG (~12%)
3. TCL (~11%) - Uses Roku OS (covered in Protocol.md)
4. Hisense (~10%) - Uses Roku OS or VIDAA
5. Sony (~7%)
6. Vizio (~5% US market)
7. Others (Android TV, Fire TV, etc.)

---

## 1. Samsung (Tizen OS)

**Protocol**: WebSocket JSON API  
**Ports**: 8001 (ws://), 8002 (wss://)  
**Discovery**: SSDP (`urn:samsung.com:device:RemoteControlReceiver:1`)

### Overview
Samsung Smart TVs (2016+) expose a WebSocket API for remote control. Older models used a legacy protocol on port 55000.

### Power/Volume Commands
```json
// Power Toggle
{
  "method": "ms.remote.control",
  "params": {
    "Cmd": "Click",
    "DataOfCmd": "KEY_POWER",
    "Option": "false",
    "TypeOfRemote": "SendRemoteKey"
  }
}

// Volume Up
{ "method": "ms.remote.control", "params": { "Cmd": "Click", "DataOfCmd": "KEY_VOLUP" } }

// Volume Down  
{ "method": "ms.remote.control", "params": { "Cmd": "Click", "DataOfCmd": "KEY_VOLDOWN" } }

// Mute
{ "method": "ms.remote.control", "params": { "Cmd": "Click", "DataOfCmd": "KEY_MUTE" } }
```

### Authentication
- First connection requires user approval on TV screen
- TV returns a token that should be stored for future connections
- Connect to: `wss://{ip}:8002/api/v2/channels/samsung.remote.control?name={base64_app_name}&token={saved_token}`

### GitHub Projects
- **samsungtvws** (Python): https://github.com/xchwarze/samsung-tv-ws-api
- **samsung-remote** (Node.js): https://github.com/nicholasbraun/samsung-remote
- **Home Assistant Integration**: https://github.com/home-assistant/core/tree/dev/homeassistant/components/samsungtv

### Notes
- Power OFF works reliably; Power ON requires Wake-on-LAN (WoL) on same network
- Some models support Art Mode (Frame TVs) via different endpoints
- SSL certificate is self-signed - must be ignored

---

## 2. LG (webOS)

**Protocol**: WebSocket with SSAP (Simple Service Access Protocol)  
**Port**: 3000 (ws://), 3001 (wss://)  
**Discovery**: SSDP (`urn:lge-com:service:webos-second-screen:1`)

### Overview
LG webOS TVs (2014+) use a well-documented WebSocket API with JSON-RPC style messaging.

### Power/Volume Commands
```json
// Power Off (no power ON via network - use WoL)
{
  "type": "request",
  "uri": "ssap://system/turnOff"
}

// Get Volume
{
  "type": "request", 
  "uri": "ssap://audio/getVolume"
}

// Set Volume (0-100)
{
  "type": "request",
  "uri": "ssap://audio/setVolume",
  "payload": { "volume": 25 }
}

// Volume Up/Down
{
  "type": "request",
  "uri": "ssap://audio/volumeUp"
}

// Mute Toggle
{
  "type": "request",
  "uri": "ssap://audio/setMute",
  "payload": { "mute": true }
}
```

### Authentication
1. Connect to WebSocket
2. TV shows pairing prompt with PIN or Accept/Deny
3. TV returns client key - store for future sessions
4. Send handshake with stored key on reconnection

### GitHub Projects
- **aiopylgtv** (Python, async): https://github.com/bendavid/aiopylgtv  
- **lgtv2** (Node.js): https://github.com/nicholasbraun/lgtv2
- **PyWebOSTV** (Python): https://github.com/supersaiyanmode/PyWebOSTV
- **Home Assistant Integration**: https://github.com/home-assistant/core/tree/dev/homeassistant/components/webostv

### Notes
- Power ON requires Wake-on-LAN
- Volume change events can be subscribed to for real-time updates
- Screen state (on/off) can be queried: `ssap://com.webos.service.tvpower/power/getPowerState`

---

## 3. TCL / Hisense (Roku OS)

See **Protocol.md** - These TVs use the standard Roku ECP protocol on port 8060.

All power/volume commands work identically to Roku streaming devices.

---

## 4. Hisense (VIDAA OS)

**Protocol**: HTTP REST API + WebSocket  
**Port**: 36669 (varies by model)  
**Discovery**: SSDP

### Overview
Hisense VIDAA TVs have a less-documented API. Some models support RemoteNow app protocol.

### Limited Documentation
- Protocol is partially reverse-engineered
- Uses JSON payloads similar to other platforms
- Authentication via 4-digit PIN shown on TV

### GitHub Projects
- **hisensetv** (Python): https://github.com/newAM/hisensetv
- **hisense-tv** (Node.js): https://github.com/nicholasbraun/hisense-tv

### Notes
- Documentation is sparse compared to Samsung/LG
- Power ON typically requires WoL
- Some models use Android TV (see below)

---

## 5. Sony (Bravia - Android TV)

**Protocol**: REST API (BRAVIA Professional Display API) + IRCC  
**Port**: 80 (HTTP)  
**Discovery**: SSDP, UPnP

### Overview
Sony Bravia TVs support both IRCC (IR-like commands over IP) and a REST API. Newer Android TV models have expanded capabilities.

### Authentication Methods
1. **Pre-Shared Key (PSK)** - Configure a static key in TV settings
2. **PIN Pairing** - TV displays PIN to enter in app

### Power/Volume Commands (IRCC)
```xml
<!-- Send via POST to http://{ip}/sony/IRCC -->
<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <u:X_SendIRCC xmlns:u="urn:schemas-sony-com:service:IRCC:1">
      <IRCCCode>AAAAAQAAAAEAAAAVAw==</IRCCCode>  <!-- Power Toggle -->
    </u:X_SendIRCC>
  </s:Body>
</s:Envelope>
```

### Common IRCC Codes
| Function | Code |
|----------|------|
| Power | `AAAAAQAAAAEAAAAVAw==` |
| Volume Up | `AAAAAQAAAAEAAAASAw==` |
| Volume Down | `AAAAAQAAAAEAAAATAw==` |
| Mute | `AAAAAQAAAAEAAAAUAw==` |

### REST API (Newer Models)
```bash
# Get Volume
curl -X POST http://{ip}/sony/audio \
  -H "X-Auth-PSK: {your_psk}" \
  -d '{"method":"getVolumeInformation","params":[],"id":1,"version":"1.0"}'

# Set Volume
curl -X POST http://{ip}/sony/audio \
  -H "X-Auth-PSK: {your_psk}" \
  -d '{"method":"setAudioVolume","params":[{"target":"speaker","volume":"25"}],"id":1,"version":"1.0"}'
```

### GitHub Projects
- **braviarc** (Python): https://github.com/aparraga/bravern
- **brern** (Python): https://github.com/jshridha/bravern  
- **sony-bravia** (Node.js): https://github.com/nicholasbraun/sony-bravia
- **Home Assistant Integration**: https://github.com/home-assistant/core/tree/dev/homeassistant/components/braviatv

### Notes
- REST API requires enabling "Remote device/Renderer" in TV settings
- WoL supported for Power ON on most models
- Some models support Google Cast for discovery

---

## 6. Vizio (SmartCast)

**Protocol**: HTTPS REST API  
**Port**: 7345, 9000  
**Discovery**: SSDP, mDNS (`_viziocast._tcp`)

### Overview
Vizio SmartCast TVs expose a REST API requiring pairing/authentication.

### Authentication
1. Initiate pairing request
2. TV displays 4-digit PIN
3. Send PIN to complete pairing
4. Receive auth token for future requests

### Power/Volume Commands
```bash
# Power Toggle
curl -k -X PUT https://{ip}:7345/key_command/ \
  -H "AUTH: {auth_token}" \
  -d '{"KEYLIST": [{"CODESET": 11, "CODE": 0, "ACTION": "KEYPRESS"}]}'

# Volume Up (CODESET: 5, CODE: 1)
# Volume Down (CODESET: 5, CODE: 0)  
# Mute Toggle (CODESET: 5, CODE: 3)
```

### GitHub Projects
- **pyvizio** (Python): https://github.com/vkorn/pyvizio
- **vizio-smart-cast** (Node.js): https://github.com/nicholasbraun/vizio-smart-cast
- **Home Assistant Integration**: https://github.com/home-assistant/core/tree/dev/homeassistant/components/vizio

### Notes
- SSL certificate is self-signed
- Power ON works via the API (doesn't require WoL)
- Input switching well supported

---

## 7. Android TV (Sony, TCL, Hisense variants, Philips)

**Protocol**: ADB (Android Debug Bridge)  
**Port**: 5555  
**Discovery**: mDNS (`_androidtvremote._tcp`)

### Overview
Android TV devices can be controlled via ADB when developer mode is enabled.

### Power/Volume via ADB
```bash
# Power key
adb shell input keyevent KEYCODE_POWER

# Volume Up
adb shell input keyevent KEYCODE_VOLUME_UP

# Volume Down
adb shell input keyevent KEYCODE_VOLUME_DOWN

# Mute
adb shell input keyevent KEYCODE_VOLUME_MUTE
```

### GitHub Projects
- **androidtvremote2** (Python): https://github.com/nicholasbraun/androidtvremote2
- **Home Assistant Integration**: https://github.com/home-assistant/core/tree/dev/homeassistant/components/androidtv

### Notes
- Requires enabling ADB debugging on TV
- Security prompt on TV for first connection
- Google TV uses same protocol

---

## 8. Amazon Fire TV

**Protocol**: ADB  
**Port**: 5555  
**Discovery**: mDNS

### Overview
Fire TV devices (sticks and TVs) use ADB protocol, same as Android TV.

### GitHub Projects
- **python-firetv** (Python): https://github.com/happyleavesaoc/python-firetv
- **Home Assistant Integration**: https://github.com/home-assistant/core/tree/dev/homeassistant/components/androidtv

---

## 9. Universal: HDMI-CEC

**Protocol**: CEC (Consumer Electronics Control) over HDMI  
**Port**: N/A (physical connection)

### Overview
HDMI-CEC allows devices connected via HDMI to control each other. A Raspberry Pi or similar device running libCEC can control TVs.

### Capabilities
- Power on/off (One Touch Play, System Standby)
- Volume control (if TV is audio system)
- Input switching

### Tools
- **libCEC**: https://github.com/Pulse-Eight/libcec
- **cec-client**: Command-line tool for CEC control
- Requires USB-CEC adapter (Pulse-Eight, etc.)

### Notes
- Works with almost any TV brand
- Requires physical HDMI connection
- Great fallback for TVs without network APIs

---

## Summary: Power/Volume Support

| Brand | Power Off | Power On | Volume | Discovery |
|-------|-----------|----------|--------|-----------|
| Samsung | ✅ WebSocket | ⚠️ WoL | ✅ Keys | SSDP |
| LG webOS | ✅ SSAP | ⚠️ WoL | ✅ API | SSDP |
| Roku (TCL/Hisense) | ✅ ECP | ✅ ECP | ✅ ECP | SSDP |
| Sony Bravia | ✅ IRCC/REST | ⚠️ WoL | ✅ IRCC/REST | SSDP/UPnP |
| Vizio | ✅ REST | ✅ REST | ✅ REST | SSDP/mDNS |
| Android TV | ✅ ADB | ⚠️ WoL | ✅ ADB | mDNS |
| Fire TV | ✅ ADB | ⚠️ WoL | ✅ ADB | mDNS |
| HDMI-CEC | ✅ CEC | ✅ CEC | ⚠️ Limited | Physical |

Legend:
- ✅ Full support
- ⚠️ Conditional (WoL = Wake-on-LAN required, or limited)

---

## Recommendations for RockYou Expansion

### High Value Targets (if expanding beyond Roku)
1. **Samsung** - Largest market share, well-documented WebSocket API
2. **LG webOS** - Second largest, excellent SSAP documentation
3. **Vizio** - US market focused, clean REST API

### Implementation Notes
- All require initial pairing/authentication flow
- Power ON universally problematic (WoL fallback needed)
- Volume control well-supported across all platforms
- Consider SSDP multi-brand discovery scan

---

---

## Wake-on-LAN (WoL) for iOS/macOS

Most TVs can't be powered ON via their network API when fully off - they need Wake-on-LAN.

### Protocol Overview
- **Port**: UDP 9 (or 7)
- **Packet**: "Magic Packet" - 6 bytes of `0xFF` + MAC address repeated 16 times
- **Target**: Broadcast address `255.255.255.255`
- **Requirement**: TV must have WoL enabled in settings, must be on same subnet

### iOS/macOS Implementation (from Roam)

Reference: `/Users/Joe/src/repos/Roam/Shared/Backend/StatelessDeviceAPI.swift`

```swift
import Network

/// Send Wake-on-LAN magic packet
/// - Parameters:
///   - macAddress: Target MAC in format "AA:BB:CC:DD:EE:FF"
///   - interface: Optional NWInterface to send on (nil = default)
@discardableResult
private func wakeOnLAN(macAddress: String, interface: NWInterface?) async -> Bool {
    let host = NWEndpoint.Host("255.255.255.255")
    let port = NWEndpoint.Port(rawValue: 9)!
    let parameters = NWParameters.udp
    if let interface {
        parameters.requiredInterface = interface
    }
    let connection = NWConnection(host: host, port: port, using: parameters)

    // Build magic packet
    var packet = Data()
    
    // Header: 6 bytes of 0xFF
    for _ in 0..<6 {
        packet.append(0xFF)
    }
    
    // MAC address repeated 16 times
    let macBytes = macAddress.split(separator: ":").compactMap { UInt8($0, radix: 16) }
    guard macBytes.count == 6 else {
        print("Invalid MAC address")
        return false
    }
    for _ in 0..<16 {
        packet.append(contentsOf: macBytes)
    }
    
    // Send via NWConnection
    return await withCheckedContinuation { continuation in
        connection.stateUpdateHandler = { state in
            if state == .ready {
                connection.send(content: packet, completion: .contentProcessed { error in
                    connection.cancel()
                    continuation.resume(returning: error == nil)
                })
            } else if case .failed = state {
                continuation.resume(returning: false)
            }
        }
        connection.start(queue: .global())
    }
}
```

### Getting MAC Address from Roku

Roku ECP provides MAC addresses in device-info:
```xml
GET /query/device-info

<device-info>
  <wifi-mac>AA:BB:CC:DD:EE:FF</wifi-mac>
  <ethernet-mac>11:22:33:44:55:66</ethernet-mac>
  ...
</device-info>
```

### Multi-Interface Approach

Roam sends WoL on ALL active interfaces to maximize success:

```swift
func sendWolToDevice(macs: [String]) async {
    // Get all UP and RUNNING network interfaces
    let interfaces = await allAddressedInterfaces().filter { iface in
        (iface.flags & UInt32(IFF_UP) != 0) && 
        (iface.flags & UInt32(IFF_RUNNING) != 0) && 
        iface.nwInterface != nil
    }
    
    // Send to each MAC on each interface
    for mac in macs {
        for iface in interfaces {
            await wakeOnLAN(macAddress: mac, interface: iface.nwInterface)
        }
        // Also try with no specific interface
        if interfaces.isEmpty {
            await wakeOnLAN(macAddress: mac, interface: nil)
        }
    }
}
```

### Power Toggle Strategy

Roam's approach for power toggle:
1. Try ECP `POST /keypress/Power` first (1.1s timeout)
2. If that fails (TV is off), send WoL to both WiFi and Ethernet MACs
3. Send on all available network interfaces

```swift
func powerToggleDevice(location: String, macs: [String]) async -> Bool {
    // Try API first
    let toggleResult = await sendKey(location: location, key: "Power", timeout: 1.1)
    
    if !toggleResult {
        // API failed (TV probably off) - try WoL
        await sendWolToDevice(macs: macs)
        return true
    }
    return true
}
```

### watchOS Limitations

⚠️ **watchOS cannot send WoL packets** - the Network framework on watchOS doesn't support raw UDP broadcast to the local network. The watch must relay power commands through the iPhone.

### Platform Comparison

| Platform | WoL Support | Notes |
|----------|-------------|-------|
| iOS | ✅ Yes | Uses Network framework, works on WiFi |
| macOS | ✅ Yes | Works on WiFi and Ethernet |
| watchOS | ❌ No | Must proxy through iPhone |

### RockYou Implementation Notes

To add WoL to RockYou:
1. Store `wifiMAC` and `ethernetMAC` in `DeviceInfo` (get from ECP device-info)
2. Create `WakeOnLAN.swift` in `Shared/Services/`
3. On power toggle when device appears offline, send WoL before/alongside ECP power command
4. Watch app should send "wake" message to iPhone via WatchConnectivity, iPhone does actual WoL

---

## References

### Home Assistant (excellent implementation reference)
- https://www.home-assistant.io/integrations/samsungtv/
- https://www.home-assistant.io/integrations/webostv/
- https://www.home-assistant.io/integrations/braviatv/
- https://www.home-assistant.io/integrations/vizio/
- https://www.home-assistant.io/integrations/androidtv/

### Protocol Documentation
- Samsung: Community reverse-engineered, no official docs
- LG webOS: https://webostv.developer.lge.com/ (limited)
- Sony Bravia: https://pro-bravia.sony.net/develop/ (professional displays)
- Roku ECP: https://developer.roku.com/docs/developer-program/dev-tools/external-control-api.md
