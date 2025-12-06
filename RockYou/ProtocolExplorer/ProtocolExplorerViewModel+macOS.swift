//
//  ProtocolExplorerViewModel.swift
//  RockYou - Protocol Explorer
//
//  View model - ECP-2 WebSocket is primary, HTTP is explicit fallback only
//

import Foundation
import SwiftUI

// MARK: - Console Entry

struct ConsoleEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: EntryType
    let content: String

    enum EntryType {
        case request
        case response
        case error
        case info

        var color: Color {
            switch self {
            case .request: return .blue
            case .response: return .green
            case .error: return .red
            case .info: return .secondary
            }
        }

        var prefix: String {
            switch self {
            case .request: return "→"
            case .response: return "←"
            case .error: return "✗"
            case .info: return "ℹ"
            }
        }
    }
}

// MARK: - View Model

@MainActor
@Observable
class ProtocolExplorerViewModel {

    // MARK: - State

    var selectedTemplate: CommandTemplate?
    var commandText: String = ""
    var consoleEntries: [ConsoleEntry] = []
    var isExecuting: Bool = false
    var placeholderValues: [String: String] = [:]

    // Device selection
    var selectedDeviceIP: String = ""

    // WebSocket state
    private var webSocketClient: RokuWebSocketClient?
    var isWebSocketConnected: Bool = false

    // Request ID counter
    private var requestCounter: Int = 0

    // MARK: - Initialization

    init() {
        addInfo("Protocol Explorer ready. ECP-2 WebSocket is primary.")
        addInfo("Select a device to connect, then pick a command.")
    }

    // MARK: - Template Selection

    func selectTemplate(_ template: CommandTemplate) {
        selectedTemplate = template
        placeholderValues = [:]

        // Auto-fill placeholders with first suggestion
        for placeholder in template.placeholders {
            if let firstSuggestion = placeholder.suggestions.first, !firstSuggestion.isEmpty {
                placeholderValues[placeholder.name] = firstSuggestion
            } else {
                placeholderValues[placeholder.name] = ""
            }
        }

        updateCommandText()
    }

    func updateCommandText() {
        guard let template = selectedTemplate else {
            commandText = ""
            return
        }

        var text = template.wsTemplate

        // Generate unique request ID
        requestCounter += 1
        text = text.replacingOccurrences(of: "<request-id>", with: "req-\(requestCounter)")

        // Substitute placeholders
        for (name, value) in placeholderValues {
            text = text.replacingOccurrences(of: "<\(name)>", with: value.isEmpty ? "<\(name)>" : value)
        }

        commandText = text
    }

    // MARK: - Device Discovery

    var discoveredDevices: [DeviceInfo] {
        RokuDiscoveryService.shared.discoveredDevices
    }

    func connectToDevice(_ ipAddress: String) {
        guard !ipAddress.isEmpty else { return }

        let deviceName = discoveredDevices.first { $0.ipAddress == ipAddress }?.name ?? ipAddress
        addInfo("🎯 Target: \(deviceName)")

        Task {
            await connectWebSocket(to: ipAddress)
        }
    }

    // MARK: - WebSocket Connection

    func connectWebSocket(to ipAddress: String) async {
        if isWebSocketConnected {
            await disconnectWebSocket()
        }

        let deviceName = discoveredDevices.first { $0.ipAddress == ipAddress }?.name ?? "Unknown"
        addInfo("Connecting ECP-2 to \(deviceName)...")

        let client = RokuWebSocketClient(
            deviceIP: ipAddress,
            deviceName: deviceName,
            onNotification: { [weak self] notification in
                self?.handleNotification(notification)
            }
        )
        webSocketClient = client

        do {
            try await client.connect()
            isWebSocketConnected = true
            addInfo("✅ ECP-2 authenticated to \(deviceName)")
        } catch {
            isWebSocketConnected = false
            addError("Connection failed: \(error.localizedDescription)")
            webSocketClient = nil
        }
    }

    func disconnectWebSocket() async {
        guard isWebSocketConnected, let client = webSocketClient else { return }
        await client.disconnect()
        webSocketClient = nil
        isWebSocketConnected = false
        addInfo("Disconnected")
    }

    private func handleNotification(_ notification: RokuNotification) {
        let message: String
        switch notification {
        case .powerModeChanged(let mode):
            message = "📢 Power: \(mode)"
        case .volumeChanged(let level, let muted):
            message = "📢 Volume: \(level)\(muted ? " (muted)" : "")"
            case .mediaPlayerStateChanged(let state, let appId, let position, let duration, let title):
                var parts: [String] = [state]
                if let appId = appId { parts.append("app:\(appId)") }
                if let title = title { parts.append("title:\(title)") }
                if let pos = position { parts.append("pos:\(pos)ms") }
                if let dur = duration { parts.append("dur:\(dur)ms") }
                message = "📢 Media: \(parts.joined(separator: ", "))"
            case .other(let type, let data):
            message = "📢 \(type): \(data)"
        }
        addResponse(message)
    }

    // MARK: - Command Execution (WebSocket - Fire and Forget)

    func executeCommand() {
        guard selectedTemplate != nil else { return }
        guard !selectedDeviceIP.isEmpty else {
            addError("No device selected.")
            return
        }

        // Compact JSON - Roku ECP-2 doesn't tolerate whitespace in JSON!
        let message = compactJSON(commandText)
        addRequest("→ \(message)")

        Task {
            await sendMessage(message)
        }
    }

    /// Send a message, reconnecting if needed
    private func sendMessage(_ message: String) async {
        // Check if we need to reconnect
        var client = webSocketClient
        var connected = false
        if let c = client {
            connected = await c.isConnected
        }

        if !connected {
            isWebSocketConnected = false
            if client != nil {
                addError("Connection lost. Reconnecting...")
            }
            await connectWebSocket(to: selectedDeviceIP)
            client = webSocketClient
        }

        guard let client = client else {
            addError("Not connected.")
            return
        }

        let stillConnected = await client.isConnected
        guard stillConnected else {
            addError("Connection failed.")
            return
        }

        do {
            try await client.sendRawFireAndForget(message) { [weak self] response in
                self?.handleRawResponse(response)
            }
        } catch {
            addError("Send failed: \(error.localizedDescription)")
            isWebSocketConnected = await client.isConnected
        }
    }

    private func handleRawResponse(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            addResponse(json)
            return
        }

        // Extract key info
        let status = obj["status"] as? String ?? "?"
        let statusMsg = obj["status-msg"] as? String ?? ""
        let response = obj["response"] as? String ?? ""

        // Build response header
        var output = "[\(response)] \(status) \(statusMsg)\n"

        // Decode content-data if present (base64 encoded)
        if let contentData = obj["content-data"] as? String,
           let decoded = Data(base64Encoded: contentData) {

            let contentType = obj["content-type"] as? String ?? ""

            if contentType.contains("xml") || contentType.contains("text") {
                // Text/XML content - show decoded
                if let text = String(data: decoded, encoding: .utf8) {
                    if text.contains("<?xml") || text.hasPrefix("<") {
                        output += "\n\(formatXML(text))"
                    } else {
                        output += "\n\(text)"
                    }
                } else {
                    output += "\n[Decoded: \(decoded.count) bytes, not UTF-8]"
                }
            } else if contentType.contains("image") {
                // Binary image data
                output += "\n[Image: \(decoded.count) bytes]"
            } else {
                // Try as text anyway
                if let text = String(data: decoded, encoding: .utf8) {
                    output += "\n\(text)"
                } else {
                    output += "\n[Binary: \(decoded.count) bytes]"
                }
            }
        } else {
            // No content-data, show the raw JSON for debugging
            let options: JSONSerialization.WritingOptions = [.prettyPrinted, Self.jsonNoEscapingSlashesOption]
            if let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: options),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                output = prettyString
            }
        }

        addResponse(output)
    }

    // MARK: - HTTP Fallback (Explicit Only)

    func executeHTTPFallback() {
        guard let template = selectedTemplate else { return }

        guard let httpTemplate = template.httpFallback else {
            addError("No HTTP fallback for this command.")
            return
        }

        if selectedDeviceIP.isEmpty {
            addError("No device selected.")
            return
        }

        Task {
            isExecuting = true
            defer { isExecuting = false }

            // Build HTTP URL from template
            var urlString = httpTemplate
            urlString = urlString.replacingOccurrences(of: "<device-ip>", with: selectedDeviceIP)
            for (name, value) in placeholderValues {
                urlString = urlString.replacingOccurrences(of: "<\(name)>", with: value)
            }

            guard let url = URL(string: urlString) else {
                addError("Invalid URL: \(urlString)")
                return
            }

            // Determine method - queries are GET, actions are POST
            let method = urlString.contains("/query/") ? "GET" : "POST"
            addRequest("HTTP \(method): \(urlString)")

            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 10

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    addError("Invalid response")
                    return
                }

                let statusLine = "HTTP \(httpResponse.statusCode)"

                if httpResponse.statusCode == 403 {
                    addError("\(statusLine) - Forbidden (Limited Mode). Use WebSocket instead.")
                    return
                }

                if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                    if text.contains("<?xml") || text.hasPrefix("<") {
                        addResponse("\(statusLine)\n\n\(formatXML(text))")
                    } else {
                        addResponse("\(statusLine)\n\n\(text)")
                    }
                } else if data.count > 0 {
                    addResponse("\(statusLine) [Binary: \(data.count) bytes]")
                } else {
                    addResponse(statusLine)
                }
            } catch {
                addError("HTTP failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Console

    private func addRequest(_ text: String) {
        consoleEntries.append(ConsoleEntry(timestamp: Date(), type: .request, content: text))
    }

    private func addResponse(_ text: String) {
        consoleEntries.append(ConsoleEntry(timestamp: Date(), type: .response, content: text))
    }

    private func addError(_ text: String) {
        consoleEntries.append(ConsoleEntry(timestamp: Date(), type: .error, content: text))
    }

    private func addInfo(_ text: String) {
        consoleEntries.append(ConsoleEntry(timestamp: Date(), type: .info, content: text))
    }

    func clearConsole() {
        consoleEntries.removeAll()
        addInfo("Console cleared")
    }

    // MARK: - Formatting

    private static var jsonNoEscapingSlashesOption: JSONSerialization.WritingOptions {
        if #available(macOS 10.15, *) {
            return [.withoutEscapingSlashes]
        } else {
            return []
        }
    }

    /// Compact JSON - Roku ECP-2 drops connection if JSON has whitespace!
    private func compactJSON(_ json: String) -> String {
        // Replace smart/curly quotes with ASCII quotes (macOS TextEditor inserts these!)
        let sanitized = json
            .replacingOccurrences(of: "\u{201C}", with: "\"")  // " left double
            .replacingOccurrences(of: "\u{201D}", with: "\"")  // " right double
            .replacingOccurrences(of: "\u{2018}", with: "'")   // ' left single
            .replacingOccurrences(of: "\u{2019}", with: "'")   // ' right single

        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let compact = try? JSONSerialization.data(withJSONObject: obj, options: Self.jsonNoEscapingSlashesOption),
              let result = String(data: compact, encoding: .utf8) else {
            return trimmed  // If it's not valid JSON, send as-is and let it fail
        }
        return result
    }

    private func formatXML(_ xml: String) -> String {
        var result = ""
        var indent = 0
        var tagContent = ""

        for char in xml {
            if char == "<" {
                let trimmed = tagContent.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    result += trimmed
                }
                tagContent = ""
                tagContent.append(char)
            } else if char == ">" {
                tagContent.append(char)

                let isClosing = tagContent.hasPrefix("</")
                let isSelfClosing = tagContent.hasSuffix("/>")

                if isClosing {
                    indent = max(0, indent - 1)
                }

                result += String(repeating: "  ", count: indent) + tagContent + "\n"

                if !isClosing && !isSelfClosing && !tagContent.hasPrefix("<?") {
                    indent += 1
                }

                tagContent = ""
            } else {
                tagContent.append(char)
            }
        }

        return result
    }
}
