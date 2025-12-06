//
//  RokuXMLFieldParser.swift
//  RockYou (Shared)
//
//  Utility for parsing "flat" Roku XML responses into a tag->value dictionary.
//  Intended primarily for /query/device-info.
//

import Foundation

public enum RokuXMLFieldParser {
  public enum Error: Swift.Error {
    case invalidXML(Swift.Error?)
  }

  /// Parse an XML document into a `[tagName: value]` dictionary.
  ///
  /// This uses a streaming XML parser (SAX-style).
  ///
  /// Behavior:
  /// - Every element produces a key.
  /// - Values are the element's direct character content (trimmed).
  /// - Self-closing tags end up as `""` (presence-only).
  /// - Attributes are ignored.
  public static func parseAllFields(_ data: Data) throws -> [String: String] {
    final class Delegate: NSObject, XMLParserDelegate {
      var stack: [(name: String, buffer: String)] = []
      var result: [String: String] = [:]

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
        _ = attributeDict
        stack.append((name: elementName, buffer: ""))
      }

      func parser(_ parser: XMLParser, foundCharacters string: String) {
        _ = parser
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].buffer.append(string)
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
        guard !stack.isEmpty else { return }

        let top = stack.removeLast()
        // Defensive: if the XML is weird, trust the callback's elementName.
        let key = elementName.isEmpty ? top.name : elementName
        let value = top.buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        result[key] = value
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
