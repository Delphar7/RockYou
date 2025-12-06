//
//  ProtocolExplorerView.swift
//  RockYou - Protocol Explorer
//
//  ECP-2 WebSocket is primary. HTTP is explicit fallback only.
//

import SwiftUI
import AppKit

struct ProtocolExplorerView: View {
    @State private var viewModel = ProtocolExplorerViewModel()
    @State private var selectedEntries: Set<UUID> = []

    var body: some View {
        NavigationSplitView {
            commandSidebar
        } detail: {
            VStack(spacing: 0) {
                deviceBar
                Divider()
                HSplitView {
                    commandEditor
                        .frame(minWidth: 340)
                    consoleView
                        .frame(minWidth: 420)
                }
            }
        }
        .navigationTitle("Protocol Explorer")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    RokuDiscoveryService.shared.startDiscovery()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    // MARK: - Device Bar

    private var deviceBar: some View {
        HStack(spacing: 16) {
            Text("Device")
                .font(.subheadline)
                .fontWeight(.medium)

            Picker("", selection: $viewModel.selectedDeviceIP) {
                Text("Select...").tag("")
                ForEach(viewModel.discoveredDevices, id: \.id) { device in
                    Text("\(device.name) (\(device.ipAddress))")
                        .tag(device.ipAddress)
                }
            }
            .labelsHidden()
            .frame(minWidth: 200)
            .onChange(of: viewModel.selectedDeviceIP) { _, newIP in
                if !newIP.isEmpty {
                    viewModel.connectToDevice(newIP)
                }
            }

            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isWebSocketConnected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(viewModel.isWebSocketConnected ? "ECP-2 Connected" : "Not Connected")
                    .font(.caption)
                    .foregroundColor(viewModel.isWebSocketConnected ? .green : .secondary)

                if viewModel.isWebSocketConnected {
                    Button("Disconnect") {
                        Task { await viewModel.disconnectWebSocket() }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sidebar

    private var commandSidebar: some View {
        List {
            ForEach(CommandTemplates.byCategory(), id: \.category) { item in
                Section(item.category.rawValue) {
                    ForEach(item.templates) { template in
                        Button {
                            viewModel.selectTemplate(template)
                        } label: {
                            HStack {
                                Text(template.name)
                                    .lineLimit(1)
                                Spacer()
                                if template.httpFallback == nil {
                                    Text("WS")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                        .opacity(AppOpacity.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                        .background(
                            viewModel.selectedTemplate?.id == template.id
                                ? Color.accentColor.opacity(AppOpacity.medium)
                                : Color.clear
                        )
                        .cornerRadius(4)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }

    // MARK: - Command Editor

    private var commandEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let template = viewModel.selectedTemplate {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.headline)
                    Text(template.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)

                Divider()

                // Placeholders
                if !template.placeholders.isEmpty {
                    Text("Parameters")
                        .font(.body)
                        .fontWeight(.medium)

                    ForEach(template.placeholders, id: \.name) { placeholder in
                        placeholderInput(placeholder)
                    }

                    Divider()
                }

                // Command JSON
                Text("WebSocket Command (ECP-2)")
                    .font(.body)
                    .fontWeight(.medium)

                CodeEditor(text: $viewModel.commandText)
                    .frame(minHeight: 140)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(AppOpacity.standard), lineWidth: 1)
                    )

                // Buttons
                HStack {
                    // HTTP fallback (if available)
                    if template.httpFallback != nil {
                        Button {
                            viewModel.executeHTTPFallback()
                        } label: {
                            Label("Send as HTTP", systemImage: "network")
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isExecuting || viewModel.selectedDeviceIP.isEmpty)
                        .help("Send via HTTP ECP-1 (fallback)")
                    } else {
                        Text("WebSocket only")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    Spacer()

                    // Main send button (WebSocket)
                    Button {
                        viewModel.executeCommand()
                    } label: {
                        HStack {
                            if viewModel.isExecuting {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Text("Send")
                        }
                        .frame(minWidth: 80)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isExecuting || !viewModel.isWebSocketConnected)
                    .keyboardShortcut(.return, modifiers: .command)
                }

            } else {
                VStack {
                    Spacer()
                    Image(systemName: "arrow.left.circle")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Select a command")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer()
        }
        .padding()
    }

    private func placeholderInput(_ placeholder: Placeholder) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(placeholder.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(placeholder.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 110, alignment: .leading)

            if !placeholder.suggestions.isEmpty {
                Picker("", selection: Binding(
                    get: { viewModel.placeholderValues[placeholder.name] ?? "" },
                    set: {
                        viewModel.placeholderValues[placeholder.name] = $0
                        viewModel.updateCommandText()
                    }
                )) {
                    ForEach(placeholder.suggestions, id: \.self) { suggestion in
                        Text(suggestion).tag(suggestion)
                    }
                }
                .labelsHidden()
            } else {
                TextField("Value", text: Binding(
                    get: { viewModel.placeholderValues[placeholder.name] ?? "" },
                    set: {
                        viewModel.placeholderValues[placeholder.name] = $0
                        viewModel.updateCommandText()
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Console

    private var consoleView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Console")
                    .font(.headline)

                if !selectedEntries.isEmpty {
                    Text("(\(selectedEntries.count) selected)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    copySelectedToClipboard()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy selected (⌘C)")
                .keyboardShortcut("c", modifiers: .command)

                Button {
                    selectedEntries.removeAll()
                    viewModel.clearConsole()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Clear")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollViewReader { proxy in
                List(selection: $selectedEntries) {
                    ForEach(viewModel.consoleEntries) { entry in
                        consoleEntryView(entry)
                            .tag(entry.id)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                }
                .listStyle(.plain)
                .background(Color(nsColor: .textBackgroundColor).opacity(AppOpacity.semiOpaque))
                .onChange(of: viewModel.consoleEntries.count) { _, _ in
                    if let last = viewModel.consoleEntries.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func consoleEntryView(_ entry: ConsoleEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entry.type.prefix)
                    .font(.body)
                    .foregroundColor(entry.type.color)
                    .fontWeight(.bold)
                Text(formatTimestamp(entry.timestamp))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text(entry.content)
                .font(.system(size: AppFontSize.body, design: .monospaced))
                .textSelection(.enabled)
                .foregroundColor(entry.type == .error ? .red : .primary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(entry.type == .error
                              ? Color.red.opacity(AppOpacity.subtle)
                              : Color(nsColor: .controlBackgroundColor))
                )
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private func copySelectedToClipboard() {
        let entries: [ConsoleEntry]
        if selectedEntries.isEmpty {
            entries = viewModel.consoleEntries
        } else {
            entries = viewModel.consoleEntries.filter { selectedEntries.contains($0.id) }
        }

        let text = entries.map { entry in
            "\(entry.type.prefix) \(formatTimestamp(entry.timestamp))\n\(entry.content)"
        }.joined(separator: "\n\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

#Preview {
    ProtocolExplorerView()
        .frame(width: 1000, height: 600)
}
