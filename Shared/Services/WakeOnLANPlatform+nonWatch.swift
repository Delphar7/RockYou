//
//  WakeOnLANPlatform+nonWatch.swift
//  RockYou (Shared)
//
//  iOS + macOS implementation for Wake-on-LAN.
//

import Foundation
import Network

extension WakeOnLANPlatform {
  static var isSupported: Bool { true }

  /// Send WoL packets for normalized MAC strings (`aa:bb:cc:dd:ee:ff`).
  ///
  /// Returns number of sends attempted (interfaces + fallback) across all MACs.
  static func sendMagicPackets(to normalizedMACs: [String]) async -> Int {
    guard !normalizedMACs.isEmpty else { return 0 }

    let interfaces = await activeBroadcastInterfaces(timeout: 0.25)
    let includeFallback = true

    var sendCount = 0
    for mac in normalizedMACs {
      guard let packet = makeMagicPacket(mac: mac) else { continue }

      // Try each active interface (best-effort).
      for iface in interfaces {
        _ = await send(packet: packet, requiredInterface: iface)
        sendCount += 1
      }

      // Also try without pinning to a specific interface (default route).
      if includeFallback {
        _ = await send(packet: packet, requiredInterface: nil)
        sendCount += 1
      }
    }

    return sendCount
  }

  // MARK: - Internals

  private static func makeMagicPacket(mac: String) -> Data? {
    // mac is normalized `aa:bb:cc:dd:ee:ff`
    let bytes = mac.split(separator: ":").compactMap { UInt8($0, radix: 16) }
    guard bytes.count == 6 else { return nil }

    var packet = Data()
    packet.reserveCapacity(6 + 16 * 6)

    // Header: 6 bytes of 0xFF
    packet.append(contentsOf: [UInt8](repeating: 0xFF, count: 6))
    // Body: MAC repeated 16 times
    for _ in 0..<16 {
      packet.append(contentsOf: bytes)
    }
    return packet
  }

  private static func send(packet: Data, requiredInterface: NWInterface?) async -> Bool {
    let host = NWEndpoint.Host("255.255.255.255")
    let port = NWEndpoint.Port(rawValue: 9)!
    let params = NWParameters.udp
    if let requiredInterface {
      params.requiredInterface = requiredInterface
    }

    // On some networks, broadcast requires allowing local endpoint reuse.
    // (This is a best-effort attempt; if unsupported, it’s ignored.)
    params.allowLocalEndpointReuse = true

    let conn = NWConnection(host: host, port: port, using: params)

    return await withCheckedContinuation { continuation in
      let lock = NSLock()
      var finished = false

      func finish(_ ok: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        continuation.resume(returning: ok)
      }

      conn.stateUpdateHandler = { state in
        switch state {
        case .ready:
          conn.send(content: packet, completion: .contentProcessed { _ in
            conn.cancel()
            finish(true)
          })
        case .failed, .cancelled:
          conn.cancel()
          finish(false)
        default:
          break
        }
      }
      conn.start(queue: DispatchQueue(label: "WakeOnLAN.send"))

      // Safety timeout: we don’t want to hang if the connection never becomes ready.
      DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
        conn.cancel()
        finish(false)
      }
    }
  }

  private static func activeBroadcastInterfaces(timeout: TimeInterval) async -> [NWInterface] {
    // Use NWPathMonitor to get current available interfaces.
    // We only care about LAN-like interfaces.
    await withTaskGroup(of: [NWInterface].self) { group in
      group.addTask {
        await withCheckedContinuation { continuation in
          let monitor = NWPathMonitor()
          let queue = DispatchQueue(label: "WakeOnLAN.path")
          monitor.pathUpdateHandler = { path in
            let ifaces = path.availableInterfaces.filter { iface in
              iface.type == .wifi || iface.type == .wiredEthernet
            }
            monitor.cancel()
            continuation.resume(returning: ifaces)
          }
          monitor.start(queue: queue)
        }
      }

      group.addTask {
        let ns = UInt64(max(0.05, timeout) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: ns)
        return []
      }

      let result = await group.next() ?? []
      group.cancelAll()
      return result
    }
  }
}
