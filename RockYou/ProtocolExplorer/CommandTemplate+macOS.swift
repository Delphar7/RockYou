//
//  CommandTemplate.swift
//  RockYou - Protocol Explorer
//
//  Command templates - ECP-2 WebSocket is primary, HTTP is optional fallback
//

import Foundation

// MARK: - Command Template Model

struct CommandTemplate: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let category: CommandCategory
    let description: String

    /// The primary WebSocket JSON command (ECP-2)
    let wsTemplate: String

    /// Optional HTTP fallback URL (ECP-1) - nil if no HTTP equivalent
    let httpFallback: String?

    /// Placeholders in the template
    let placeholders: [Placeholder]

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CommandTemplate, rhs: CommandTemplate) -> Bool {
        lhs.id == rhs.id
    }
}

enum CommandCategory: String, CaseIterable {
    case control = "Control"
    case query = "Queries"
    case events = "Events"
    case audio = "Audio"
    case developer = "Developer Tools"
    case custom = "Custom"
}

struct Placeholder: Hashable {
    let name: String
    let description: String
    let suggestions: [String]

    static let key = Placeholder(
        name: "key",
        description: "Remote key name",
        suggestions: [
            "Home", "Rev", "Fwd", "Play", "Select", "Left", "Right", "Down", "Up", "Back",
            "InstantReplay", "Info", "Backspace", "Search", "Enter", "VolumeDown", "VolumeUp",
            "VolumeMute", "Power", "PowerOn", "PowerOff", "ChannelUp", "ChannelDown",
            "InputTuner", "InputHDMI1", "InputHDMI2", "InputHDMI3", "InputHDMI4", "InputAV1"
        ]
    )

    static let appId = Placeholder(
        name: "app-id",
        description: "Roku app/channel ID",
        suggestions: ["12", "13", "837", "2285", "291097", "61322", "593099"]  // Netflix, Prime, YouTube, Hulu, Disney+, Max, Peacock
    )

    static let channelId = Placeholder(
        name: "channel-id",
        description: "Roku channel ID (use \"dev\" for sideloaded dev channel)",
        suggestions: ["dev", "12", "13", "837", "2285"]
    )

    static let tvChannel = Placeholder(
        name: "ch",
        description: "TV channel number (Roku TV tuner) e.g. 1.1",
        suggestions: ["1.1", "2.1", "7.1"]
    )

    static let queryString = Placeholder(
        name: "query-string",
        description: "Raw query string (URL encoded), e.g. key=value&key2=value2",
        suggestions: ["contentID=123&mediaType=movie", "keyword=Star%20Trek&launch=true"]
    )

    static let nodeId = Placeholder(
        name: "node-id",
        description: "SceneGraph node id",
        suggestions: []
    )

    static let durationSeconds = Placeholder(
        name: "duration-seconds",
        description: "Duration in seconds",
        suggestions: ["1", "5", "10", "30", "60"]
    )

    static let escaped = Placeholder(
        name: "escaped",
        description: "Escape special characters (true/false)",
        suggestions: ["true", "false"]
    )

    static let keys = Placeholder(
        name: "keys",
        description: "Registry keys OR'd together, e.g. keyA|keyB",
        suggestions: []
    )

    static let sections = Placeholder(
        name: "sections",
        description: "Registry sections OR'd together, e.g. sectionA|sectionB",
        suggestions: []
    )

    static let contentId = Placeholder(
        name: "content-id",
        description: "Content ID for deep linking",
        suggestions: []
    )

    static let mediaType = Placeholder(
        name: "media-type",
        description: "Media type for deep linking",
        suggestions: ["movie", "episode", "series", "short-form-video", "live"]
    )

    static let text = Placeholder(
        name: "text",
        description: "Text to send",
        suggestions: []
    )
}

// MARK: - Built-in Command Templates (ECP-2 Primary)

struct CommandTemplates {

    // MARK: - Control Commands

    static let keyPress = CommandTemplate(
        name: "Key Press",
        category: .control,
        description: "Send a remote key press",
        wsTemplate: """
        {
          "request": "key-press",
          "request-id": "<request-id>",
          "param-key": "<key>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/keypress/<key>",
        placeholders: [.key]
    )

    static let keyDown = CommandTemplate(
        name: "Key Down",
        category: .control,
        description: "Send key down event (hold)",
        wsTemplate: """
        {
          "request": "key-down",
          "request-id": "<request-id>",
          "param-key": "<key>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/keydown/<key>",
        placeholders: [.key]
    )

    static let keyUp = CommandTemplate(
        name: "Key Up",
        category: .control,
        description: "Send key up event (release)",
        wsTemplate: """
        {
          "request": "key-up",
          "request-id": "<request-id>",
          "param-key": "<key>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/keyup/<key>",
        placeholders: [.key]
    )

    static let launch = CommandTemplate(
        name: "Launch App",
        category: .control,
        description: "Launch an app/channel",
        wsTemplate: """
        {
          "request": "launch",
          "request-id": "<request-id>",
          "param-channel-id": "<app-id>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/launch/<app-id>",
        placeholders: [.appId]
    )

    static let launchWithContent = CommandTemplate(
        name: "Launch with Deep Link",
        category: .control,
        description: "Launch app with content parameters",
        wsTemplate: """
        {
          "request": "launch",
          "request-id": "<request-id>",
          "param-channel-id": "<app-id>",
          "param-contentid": "<content-id>",
          "param-mediatype": "<media-type>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/launch/<app-id>?contentId=<content-id>&mediaType=<media-type>",
        placeholders: [.appId, .contentId, .mediaType]
    )

    static let installAppUnverified = CommandTemplate(
        name: "Install App (Unverified)",
        category: .control,
        description: "Best guess ECP-2 mapping for ECP-1 POST /install/<app-id>",
        wsTemplate: """
        {
          "request": "install",
          "request-id": "<request-id>",
          "param-channel-id": "<app-id>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/install/<app-id>",
        placeholders: [.appId]
    )

    static let installWithDeepLinkUnverified = CommandTemplate(
        name: "Install with Deep Link (Unverified)",
        category: .control,
        description: "Best guess ECP-2 mapping for ECP-1 POST /install/<app-id>?contentId=...&mediaType=...",
        wsTemplate: """
        {
          "request": "install",
          "request-id": "<request-id>",
          "param-channel-id": "<app-id>",
          "param-contentid": "<content-id>",
          "param-mediatype": "<media-type>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/install/<app-id>?contentId=<content-id>&mediaType=<media-type>",
        placeholders: [.appId, .contentId, .mediaType]
    )

    static let launchTVTunerUnverified = CommandTemplate(
        name: "Launch TV Tuner (Unverified)",
        category: .control,
        description: "Roku TV only. Best guess for ECP-1 POST /launch/tvinput.dtv?ch=1.1",
        wsTemplate: """
        {
          "request": "launch",
          "request-id": "<request-id>",
          "param-channel-id": "tvinput.dtv",
          "param-ch": "<ch>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/launch/tvinput.dtv?ch=<ch>",
        placeholders: [.tvChannel]
    )

    static let sendText = CommandTemplate(
        name: "Send Text",
        category: .control,
        description: "Send text input (for search fields)",
        wsTemplate: """
        {
          "request": "type",
          "request-id": "<request-id>",
          "param-text": "<text>"
        }
        """,
        httpFallback: nil,  // No HTTP equivalent for bulk text
        placeholders: [.text]
    )

    // MARK: - Query Commands

    static let queryDeviceInfo = CommandTemplate(
        name: "Device Info",
        category: .query,
        description: "Get device information (model, serial, software version)",
        wsTemplate: """
        {
          "request": "query-device-info",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/query/device-info",
        placeholders: []
    )

    static let queryApps = CommandTemplate(
        name: "Installed Apps",
        category: .query,
        description: "List all installed channels/apps",
        wsTemplate: """
        {
          "request": "query-apps",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/query/apps",
        placeholders: []
    )

    static let queryActiveApp = CommandTemplate(
        name: "Active App",
        category: .query,
        description: "Get currently running app",
        wsTemplate: """
        {
          "request": "query-active-app",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/query/active-app",
        placeholders: []
    )

    static let queryMediaPlayer = CommandTemplate(
        name: "Media Player State",
        category: .query,
        description: "Get media player state (playing, paused, position)",
        wsTemplate: """
        {
          "request": "query-media-player",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/query/media-player",
        placeholders: []
    )

    static let queryIcon = CommandTemplate(
        name: "App Icon",
        category: .query,
        description: "Get app icon image",
        wsTemplate: """
        {
          "request": "query-icon",
          "request-id": "<request-id>",
          "param-channel-id": "<app-id>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/query/icon/<app-id>",
        placeholders: [.appId]
    )

    static let queryTVChannelsUnverified = CommandTemplate(
        name: "TV Channels (Unverified)",
        category: .query,
        description: "Roku TV only. Best guess for ECP-1 GET /query/tv-channels",
        wsTemplate: """
        {
          "request": "query-tv-channels",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/query/tv-channels",
        placeholders: []
    )

    static let queryTVActiveChannelUnverified = CommandTemplate(
        name: "TV Active Channel (Unverified)",
        category: .query,
        description: "Roku TV only. Best guess for ECP-1 GET /query/tv-active-channel",
        wsTemplate: """
        {
          "request": "query-tv-active-channel",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/query/tv-active-channel",
        placeholders: []
    )

    static let queryAudioDevice = CommandTemplate(
        name: "Audio Device",
        category: .query,
        description: "Get audio device/output information",
        wsTemplate: """
        {
          "request": "query-audio-device",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: nil,
        placeholders: []
    )

    static let queryTexteditState = CommandTemplate(
        name: "Text Edit State",
        category: .query,
        description: "Get current text input field state",
        wsTemplate: """
        {
          "request": "query-textedit-state",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: nil,
        placeholders: []
    )

    // MARK: - HTTP-Style Commands (Unverified ECP-2 mappings)

    static let inputUnverified = CommandTemplate(
        name: "Input (Unverified)",
        category: .custom,
        description: "Best guess ECP-2 mapping for ECP-1 POST /input?<query-string>",
        wsTemplate: """
        {
          "request": "input",
          "request-id": "<request-id>",
          "param-query-string": "<query-string>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/input?<query-string>",
        placeholders: [.queryString]
    )

    static let searchUnverified = CommandTemplate(
        name: "Search (Unverified)",
        category: .custom,
        description: "Best guess ECP-2 mapping for ECP-1 POST /search?<query-string>",
        wsTemplate: """
        {
          "request": "search",
          "request-id": "<request-id>",
          "param-query-string": "<query-string>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/search?<query-string>",
        placeholders: [.queryString]
    )

    // MARK: - Developer Tools (UnverifiedDeveloper)

    static let queryR2D2BitmapsUnverifiedDeveloper = CommandTemplate(
        name: "Query r2d2-bitmaps (UnverifiedDeveloper)",
        category: .developer,
        description: "Developer mode. Best guess for ECP-1 GET /query/r2d2-bitmaps",
        wsTemplate: """
        {
          "request": "query-r2d2-bitmaps",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/query/r2d2-bitmaps",
        placeholders: []
    )

    static let queryGraphicsFrameRateUnverifiedDeveloper = CommandTemplate(
        name: "Query graphics-frame-rate (UnverifiedDeveloper)",
        category: .developer,
        description: "Developer mode. Best guess for ECP-1 GET /query/graphics-frame-rate",
        wsTemplate: """
        {
          "request": "query-graphics-frame-rate",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/query/graphics-frame-rate",
        placeholders: []
    )

    static let queryFWBeaconsUnverifiedDeveloper = CommandTemplate(
        name: "Query fwbeacons (UnverifiedDeveloper)",
        category: .developer,
        description: "Developer mode. Best guess for ECP-1 GET /query/fwbeacons",
        wsTemplate: """
        {
          "request": "query-fwbeacons",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/query/fwbeacons",
        placeholders: []
    )

    static let fwBeaconsTrackUnverifiedDeveloper = CommandTemplate(
        name: "fwbeacons track (UnverifiedDeveloper)",
        category: .developer,
        description: "Developer mode. Best guess for ECP-1 POST /fwbeacons/track/<channel-id> (or /fwbeacons/track)",
        wsTemplate: """
        {
          "request": "fwbeacons-track",
          "request-id": "<request-id>",
          "param-channel-id": "<channel-id>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/fwbeacons/track/<channel-id>",
        placeholders: [.channelId]
    )

    static let fwBeaconsUntrackUnverifiedDeveloper = CommandTemplate(
        name: "fwbeacons untrack (UnverifiedDeveloper)",
        category: .developer,
        description: "Developer mode. Best guess for ECP-1 POST /fwbeacons/untrack",
        wsTemplate: """
        {
          "request": "fwbeacons-untrack",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/fwbeacons/untrack",
        placeholders: []
    )

    static let querySGNodesAllUnverifiedDeveloper = CommandTemplate(
        name: "Query sgnodes/all (UnverifiedDeveloper)",
        category: .developer,
        description: "Developer mode. Best guess for ECP-1 GET /query/sgnodes/all",
        wsTemplate: """
        {
          "request": "query-sgnodes-all",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/query/sgnodes/all",
        placeholders: []
    )

    static let querySGNodesRootsUnverifiedDeveloper = CommandTemplate(
        name: "Query sgnodes/roots (UnverifiedDeveloper)",
        category: .developer,
        description: "Developer mode. Best guess for ECP-1 GET /query/sgnodes/roots",
        wsTemplate: """
        {
          "request": "query-sgnodes-roots",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/query/sgnodes/roots",
        placeholders: []
    )

    static let querySGNodesNodeUnverifiedDeveloper = CommandTemplate(
        name: "Query sgnodes/node (UnverifiedDeveloper)",
        category: .developer,
        description: "Developer mode. Best guess for ECP-1 GET /query/sgnodes/nodes?node-id=<node-id>",
        wsTemplate: """
        {
          "request": "query-sgnodes-nodes",
          "request-id": "<request-id>",
          "param-node-id": "<node-id>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/query/sgnodes/nodes?node-id=<node-id>",
        placeholders: [.nodeId]
    )

    static let queryChanPerfUnverifiedDeveloper = CommandTemplate(
        name: "Query chanperf (UnverifiedDeveloper)",
        category: .developer,
        description: "Developer mode. Best guess for ECP-1 GET /query/chanperf",
        wsTemplate: """
        {
          "request": "query-chanperf",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/query/chanperf",
        placeholders: []
    )

    static let queryChanPerfForChannelUnverifiedDeveloper = CommandTemplate(
        name: "Query chanperf/<channel-id> (UnverifiedDeveloper)",
        category: .developer,
        description: "Developer mode. Best guess for ECP-1 GET /query/chanperf/<channel-id>?duration-seconds=<duration-seconds>",
        wsTemplate: """
        {
          "request": "query-chanperf-channel",
          "request-id": "<request-id>",
          "param-channel-id": "<channel-id>",
          "param-duration-seconds": "<duration-seconds>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/query/chanperf/<channel-id>?duration-seconds=<duration-seconds>",
        placeholders: [.channelId, .durationSeconds]
    )

    static let queryRegistryUnverifiedDeveloper = CommandTemplate(
        name: "Query registry/<channel-id> (UnverifiedDeveloper)",
        category: .developer,
        description: "Developer mode. Best guess for ECP-1 GET /query/registry/<channel-id>?keys=...&sections=...&escaped=...",
        wsTemplate: """
        {
          "request": "query-registry",
          "request-id": "<request-id>",
          "param-channel-id": "<channel-id>",
          "param-keys": "<keys>",
          "param-sections": "<sections>",
          "param-escaped": "<escaped>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/query/registry/<channel-id>?keys=<keys>&sections=<sections>&escaped=<escaped>",
        placeholders: [.channelId, .keys, .sections, .escaped]
    )

    static let querySGRendezvousUnverifiedDeveloper = CommandTemplate(
        name: "Query sgrendezvous (UnverifiedDeveloper)",
        category: .developer,
        description: "Developer mode. Best guess for ECP-1 GET /query/sgrendezvous",
        wsTemplate: """
        {
          "request": "query-sgrendezvous",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/query/sgrendezvous",
        placeholders: []
    )

    static let sgrendezvousTrackUnverifiedDeveloper = CommandTemplate(
        name: "sgrendezvous track (UnverifiedDeveloper)",
        category: .developer,
        description: "Developer mode. Best guess for ECP-1 POST /sgrendezvous/track",
        wsTemplate: """
        {
          "request": "sgrendezvous-track",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/sgrendezvous/track",
        placeholders: []
    )

    static let sgrendezvousUntrackUnverifiedDeveloper = CommandTemplate(
        name: "sgrendezvous untrack (UnverifiedDeveloper)",
        category: .developer,
        description: "Developer mode. Best guess for ECP-1 POST /sgrendezvous/untrack",
        wsTemplate: """
        {
          "request": "sgrendezvous-untrack",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: "http://<device-ip>:8060/sgrendezvous/untrack",
        placeholders: []
    )

    // MARK: - Event Subscriptions (WebSocket only)

    static let requestAppStateEvents = CommandTemplate(
        name: "Subscribe: App State",
        category: .events,
        description: "Subscribe to app state change notifications",
        wsTemplate: """
        {
          "request": "request-app-state-event",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: nil,
        placeholders: []
    )

    static let requestMediaEvents = CommandTemplate(
        name: "Subscribe: Media Player",
        category: .events,
        description: "Subscribe to media player event notifications",
        wsTemplate: """
        {
          "request": "request-media-event",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: nil,
        placeholders: []
    )

    static let requestAudioEvents = CommandTemplate(
        name: "Subscribe: Audio",
        category: .events,
        description: "Subscribe to audio/volume event notifications",
        wsTemplate: """
        {
          "request": "request-audio-event",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: nil,
        placeholders: []
    )

    // MARK: - Audio Control (WebSocket only)

    static let setVolume = CommandTemplate(
        name: "Set Volume",
        category: .audio,
        description: "Set volume level (0-100)",
        wsTemplate: """
        {
          "request": "set-volume",
          "request-id": "<request-id>",
          "param-volume": "<volume>"
        }
        """,
        httpFallback: nil,
        placeholders: [Placeholder(name: "volume", description: "Volume level 0-100", suggestions: ["0", "25", "50", "75", "100"])]
    )

    static let setMute = CommandTemplate(
        name: "Set Mute",
        category: .audio,
        description: "Mute or unmute audio",
        wsTemplate: """
        {
          "request": "set-mute",
          "request-id": "<request-id>",
          "param-mute": "<mute>"
        }
        """,
        httpFallback: nil,
        placeholders: [Placeholder(name: "mute", description: "true or false", suggestions: ["true", "false"])]
    )

    // MARK: - Custom

    static let customCommand = CommandTemplate(
        name: "Custom JSON",
        category: .custom,
        description: "Send any WebSocket JSON command",
        wsTemplate: """
        {
          "request": "<command>",
          "request-id": "<request-id>"
        }
        """,
        httpFallback: nil,
        placeholders: [Placeholder(name: "command", description: "ECP-2 request type", suggestions: [])]
    )

    // MARK: - All Templates by Category

    static let all: [CommandTemplate] = [
        // Control
        keyPress, keyDown, keyUp, launch, launchWithContent, installAppUnverified, installWithDeepLinkUnverified, launchTVTunerUnverified, sendText,
        // Queries
        queryDeviceInfo, queryApps, queryActiveApp, queryMediaPlayer, queryIcon, queryTVChannelsUnverified, queryTVActiveChannelUnverified, queryAudioDevice, queryTexteditState,
        // Events
        requestAppStateEvents, requestMediaEvents, requestAudioEvents,
        // Audio
        setVolume, setMute,
        // Developer Tools
        queryR2D2BitmapsUnverifiedDeveloper,
        queryGraphicsFrameRateUnverifiedDeveloper,
        queryFWBeaconsUnverifiedDeveloper,
        fwBeaconsTrackUnverifiedDeveloper,
        fwBeaconsUntrackUnverifiedDeveloper,
        querySGNodesAllUnverifiedDeveloper,
        querySGNodesRootsUnverifiedDeveloper,
        querySGNodesNodeUnverifiedDeveloper,
        queryChanPerfUnverifiedDeveloper,
        queryChanPerfForChannelUnverifiedDeveloper,
        queryRegistryUnverifiedDeveloper,
        querySGRendezvousUnverifiedDeveloper,
        sgrendezvousTrackUnverifiedDeveloper,
        sgrendezvousUntrackUnverifiedDeveloper,
        // Custom
        inputUnverified, searchUnverified, customCommand
    ]

    static func byCategory() -> [(category: CommandCategory, templates: [CommandTemplate])] {
        CommandCategory.allCases.compactMap { category in
            let templates = all.filter { $0.category == category }
            return templates.isEmpty ? nil : (category, templates)
        }
    }
}
