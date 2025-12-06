//
//  NetworkInfo.swift
//  RockYou (Shared)
//
//  Network information retrieval (subnet mask) for the local interface.
//  Note: MAC addresses come from Roku device-info query, not local interfaces.
//

import Foundation
import Network
import SystemConfiguration
import Darwin

/// Platform-specific network information provider
public enum NetworkInfoProvider {
  /// Get subnet mask for the interface that can reach the given IP address
  public static func subnetMask(for ipAddress: String) -> String? {
    // Find the interface that can reach this IP
    guard let (_, netmask) = findInterfaceForIP(ipAddress), let netmask = netmask else {
      return nil
    }

    // Extract subnet mask string
    return extractSubnetMask(from: netmask)
  }
}

// MARK: - Shared Helper Functions

/// Find the network interface that can reach the target IP address
/// Returns: (interface IP, netmask) if found, nil otherwise
private func findInterfaceForIP(_ targetIP: String) -> (interfaceIP: String, netmask: UnsafeMutablePointer<sockaddr>?)? {
  var ifaddr: UnsafeMutablePointer<ifaddrs>?
  guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
    return nil
  }
  defer { freeifaddrs(ifaddr) }

  // Find the interface that can reach the target IP
  for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
    let interface = ptr.pointee
    let addrFamily = interface.ifa_addr.pointee.sa_family

    if addrFamily == UInt8(AF_INET) {
      var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      if getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                    &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
        let interfaceIP = String(cString: hostname)

        // Check if this interface can reach the target IP (same subnet check)
        if isSameSubnet(interfaceIP: interfaceIP, targetIP: targetIP, netmask: interface.ifa_netmask) {
          return (interfaceIP, interface.ifa_netmask)
        }
      }
    }
  }

  return nil
}

/// Check if two IP addresses are on the same subnet given a netmask
private func isSameSubnet(interfaceIP: String, targetIP: String, netmask: UnsafeMutablePointer<sockaddr>?) -> Bool {
  guard let netmask = netmask else { return false }

  let interfaceParts = interfaceIP.split(separator: ".").compactMap { Int($0) }
  let targetParts = targetIP.split(separator: ".").compactMap { Int($0) }

  guard interfaceParts.count == 4, targetParts.count == 4 else { return false }

  var netmaskHostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
  guard getnameinfo(netmask, socklen_t(netmask.pointee.sa_len),
                   &netmaskHostname, socklen_t(netmaskHostname.count), nil, 0, NI_NUMERICHOST) == 0 else {
    return false
  }

  let netmaskStr = String(cString: netmaskHostname)
  let netmaskParts = netmaskStr.split(separator: ".").compactMap { Int($0) }
  guard netmaskParts.count == 4 else { return false }

  // Check if interface IP and target IP are on same subnet
  for i in 0..<4 {
    if (interfaceParts[i] & netmaskParts[i]) != (targetParts[i] & netmaskParts[i]) {
      return false
    }
  }

  return true
}

/// Extract subnet mask string from a sockaddr netmask
private func extractSubnetMask(from netmask: UnsafeMutablePointer<sockaddr>) -> String? {
  var netmaskHostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
  guard getnameinfo(netmask, socklen_t(netmask.pointee.sa_len),
                   &netmaskHostname, socklen_t(netmaskHostname.count), nil, 0, NI_NUMERICHOST) == 0 else {
    return nil
  }
  return String(cString: netmaskHostname)
}
