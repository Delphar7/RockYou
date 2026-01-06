//
//  RokuAudioDevice.swift
//  RockYou (Shared)
//
//  Typed model + XML parser for ECP-2 `query-audio-device`.
//

import Foundation

public struct RokuAudioDevice: Sendable, Equatable {
  public struct Global: Sendable, Equatable {
    public var muted: Bool?
    public var volume: Int?
    public var destinationList: [String] = []
  }

  public struct Destination: Sendable, Equatable {
    public var name: String
    public var muted: Bool?
    public var volume: Int?
  }

  public var allDestinations: [String] = []
  public var global: Global = .init()
  public var destinations: [Destination] = []

  public init() {}
}

public enum RokuAudioDeviceParser {
  public enum Error: Swift.Error {
    case invalidXML(Swift.Error?)
  }

  public static func parse(_ data: Data) throws -> RokuAudioDevice {
    final class Delegate: NSObject, XMLParserDelegate {
      var elementStack: [String] = []
      var buffer: String = ""

      var result = RokuAudioDevice()

      var currentDestinationName: String?
      var currentDestinationMuted: Bool?
      var currentDestinationVolume: Int?

      func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
      ) {
        _ = parser
        _ = namespaceURI
        _ = qName
        buffer = ""
        elementStack.append(elementName)

        if elementName == "destination" {
          currentDestinationName = attributeDict["name"]
          currentDestinationMuted = nil
          currentDestinationVolume = nil
        }
      }

      func parser(_ parser: XMLParser, foundCharacters string: String) {
        _ = parser
        buffer.append(string)
      }

      func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
      ) {
        _ = parser
        _ = namespaceURI
        _ = qName

        defer {
          if !elementStack.isEmpty { _ = elementStack.removeLast() }
          buffer = ""
        }

        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
          // Still need to finalize destination blocks even if value is empty.
          if elementName == "destination" { finalizeDestinationIfNeeded() }
          return
        }

        // Convenience helpers
        func boolValue(_ s: String) -> Bool? {
          switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
          case "true": return true
          case "false": return false
          default: return nil
          }
        }

        // Match on full XML path so nested <volume>/<muted> doesn't collide.
        let path = elementStack.joined(separator: "/")

        switch path {
        case "audio-device/capabilities/all-destinations":
          result.allDestinations = value.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
          }.filter { !$0.isEmpty }

        case "audio-device/global/muted":
          result.global.muted = boolValue(value)
        case "audio-device/global/volume":
          result.global.volume = Int(value)
        case "audio-device/global/destination-list":
          result.global.destinationList = value.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
          }.filter { !$0.isEmpty }

        default:
          break
        }

        // Destination-scoped parsing: we key off the tail element name but only when
        // we're inside a <destination ...> block.
        if currentDestinationName != nil {
          switch elementName {
          case "muted":
            // Only accept when within destinations/destination/... (avoid other "muted" tags)
            if path.hasPrefix("audio-device/destinations/destination") {
              currentDestinationMuted = boolValue(value)
            }
          case "volume":
            if path.hasPrefix("audio-device/destinations/destination") {
              currentDestinationVolume = Int(value)
            }
          default:
            break
          }
        }

        if elementName == "destination" { finalizeDestinationIfNeeded() }
      }

      private func finalizeDestinationIfNeeded() {
        guard let name = currentDestinationName, !name.isEmpty else {
          currentDestinationName = nil
          currentDestinationMuted = nil
          currentDestinationVolume = nil
          return
        }

        result.destinations.append(
          RokuAudioDevice.Destination(
            name: name,
            muted: currentDestinationMuted,
            volume: currentDestinationVolume
          )
        )

        currentDestinationName = nil
        currentDestinationMuted = nil
        currentDestinationVolume = nil
      }
    }

    let delegate = Delegate()
    let parser = XMLParser(data: data)
    parser.delegate = delegate

    let ok = parser.parse()
    if !ok {
      throw Error.invalidXML(parser.parserError)
    }
    return delegate.result
  }
}
