//
//  AppBranding.swift
//  RockYou (Shared)
//
//  Brand colors and initials for app placeholders.
//  Used when app icons are loading or unavailable.
//
//  App IDs are stable Roku channel store identifiers - same worldwide.
//  https://channelstore.roku.com/details/{id}
//

import SwiftUI

// MARK: - Known Roku App IDs

/// Stable Roku channel store IDs (same across all regions/languages)
/// Verified from actual device dump - December 2025
enum RokuAppID {
  // === Major Streaming Services ===
  static let netflix = "12"
  static let primeVideo = "13"
  static let youtube = "837"
  static let youtubeTV = "195316"
  static let hulu = "2285"
  static let disneyPlus = "291097"
  static let max = "61322"              // HBO Max / Max
  static let peacock = "593099"
  static let paramountPlus = "31440"
  static let appleTVPlus = "551012"
  static let appleMusic = "637193"

  // === Media & Entertainment ===
  static let plex = "13535"
  static let plutoTV = "74519"
  static let tubi = "41468"
  static let crunchyroll = "2595"
  static let fandangoAtHome = "13842"   // Formerly Vudu
  static let showtime = "8838"
  static let starz = "65067"
  static let slingTV = "46041"
  static let amcPlus = "636527"
  static let theRokuChannel = "151908"
  static let theCW = "111255"
  static let nbc = "68669"
  static let adultSwim = "187665"
  static let discoveryGO = "96041"
  static let hgtvGO = "75619"
  static let dropout = "253232"
  static let vix = "552828"             // Spanish streaming

  // === Sports ===
  static let espn = "34376"
  static let nfl = "44856"
  static let nflSundayTicket = "63772"

  // === Kids ===
  static let pbsKids = "23333"
  static let kidsFamily = "606242"      // Kids & Family on Roku Channel

  // === System ===
  static let rokuMediaPlayer = "2213"
  static let rokuChannel = "151908"
}

// MARK: - App Branding

enum AppBranding {

  /// Get branded abbreviation for an app
  /// Primary: Match by app ID (stable)
  /// Fallback: Match by name, then first 2 letters
  static func initials(for name: String, appId: String? = nil) -> String {
    // Try ID-based lookup first (most reliable)
    if let id = appId, let abbrev = abbreviationsByID[id] {
      return abbrev
    }

    // Fallback: name matching (for unknown IDs)
    for (key, abbrev) in abbreviationsByName {
      if name.localizedCaseInsensitiveContains(key) {
        return abbrev
      }
    }

    // Final fallback: first 2 letters
    let letters = name.filter { $0.isLetter }
    return String(letters.prefix(2)).uppercased()
  }

  /// Get brand color for an app
  /// Primary: Match by app ID (stable)
  /// Fallback: Match by name, then Roku purple
  static func color(for name: String, appId: String? = nil) -> Color {
    // Try ID-based lookup first
    if let id = appId, let color = colorsByID[id] {
      return color
    }

    // Fallback: name matching
    for (key, color) in colorsByName {
      if name.localizedCaseInsensitiveContains(key) {
        return color
      }
    }

    return rokuPurple.opacity(AppOpacity.primary)
  }


  // MARK: - Brand Data by ID (Primary - Stable)

  private static let abbreviationsByID: [String: String] = [
    // Major streaming
    RokuAppID.netflix: "N",
    RokuAppID.primeVideo: "P",
    RokuAppID.youtube: "YT",
    RokuAppID.youtubeTV: "YT",
    RokuAppID.hulu: "H",
    RokuAppID.disneyPlus: "D+",
    RokuAppID.max: "MAX",
    RokuAppID.peacock: "🦚",
    RokuAppID.paramountPlus: "P+",
    RokuAppID.appleTVPlus: "tv",
    RokuAppID.appleMusic: "♫",

    // Media & Entertainment
    RokuAppID.plex: "▶",
    RokuAppID.plutoTV: "P",
    RokuAppID.tubi: "T",
    RokuAppID.crunchyroll: "CR",
    RokuAppID.fandangoAtHome: "F",
    RokuAppID.showtime: "SHO",
    RokuAppID.starz: "★",
    RokuAppID.slingTV: "S",
    RokuAppID.amcPlus: "AMC",
    RokuAppID.theRokuChannel: "R",
    RokuAppID.theCW: "CW",
    RokuAppID.nbc: "NBC",
    RokuAppID.adultSwim: "AS",
    RokuAppID.discoveryGO: "D",
    RokuAppID.hgtvGO: "H",
    RokuAppID.dropout: "DO",
    RokuAppID.vix: "ViX",

    // Sports
    RokuAppID.espn: "ESPN",
    RokuAppID.nfl: "NFL",
    RokuAppID.nflSundayTicket: "🏈",

    // Kids
    RokuAppID.pbsKids: "PBS",
    RokuAppID.kidsFamily: "K",

    // System
    RokuAppID.rokuMediaPlayer: "▶",
  ]

  private static let colorsByID: [String: Color] = [
    // Major streaming
    RokuAppID.netflix: Color(red: 0.89, green: 0.09, blue: 0.14),      // Netflix Red
    RokuAppID.primeVideo: Color(red: 0.0, green: 0.67, blue: 0.86),    // Prime Blue
    RokuAppID.youtube: Color(red: 1.0, green: 0.0, blue: 0.0),         // YouTube Red
    RokuAppID.youtubeTV: Color(red: 1.0, green: 0.0, blue: 0.0),
    RokuAppID.hulu: Color(red: 0.11, green: 0.85, blue: 0.45),         // Hulu Green
    RokuAppID.disneyPlus: Color(red: 0.07, green: 0.21, blue: 0.55),   // Disney Blue
    RokuAppID.max: Color(red: 0.0, green: 0.27, blue: 0.82),           // Max Blue
    RokuAppID.peacock: Color(red: 0.0, green: 0.0, blue: 0.0),         // Peacock Black
    RokuAppID.paramountPlus: Color(red: 0.0, green: 0.35, blue: 0.74), // Paramount Blue
    RokuAppID.appleTVPlus: Color(red: 0.2, green: 0.2, blue: 0.2),     // Apple Dark
    RokuAppID.appleMusic: Color(red: 0.98, green: 0.24, blue: 0.42),   // Apple Music Pink

    // Media & Entertainment
    RokuAppID.plex: Color(red: 0.91, green: 0.67, blue: 0.15),         // Plex Orange
    RokuAppID.plutoTV: Color(red: 0.0, green: 0.0, blue: 0.0),         // Pluto Black
    RokuAppID.tubi: Color(red: 0.98, green: 0.24, blue: 0.24),         // Tubi Orange-Red
    RokuAppID.crunchyroll: Color(red: 0.95, green: 0.51, blue: 0.13),  // Crunchyroll Orange
    RokuAppID.fandangoAtHome: Color(red: 0.2, green: 0.6, blue: 0.86), // Fandango Blue
    RokuAppID.showtime: Color(red: 0.8, green: 0.0, blue: 0.0),        // Showtime Red
    RokuAppID.starz: Color(red: 0.0, green: 0.0, blue: 0.0),           // Starz Black
    RokuAppID.slingTV: Color(red: 0.15, green: 0.35, blue: 0.65),      // Sling Blue
    RokuAppID.amcPlus: Color(red: 0.0, green: 0.0, blue: 0.0),         // AMC Black
    RokuAppID.theRokuChannel: rokuPurple,
    RokuAppID.theCW: Color(red: 0.0, green: 0.5, blue: 0.0),           // CW Green
    RokuAppID.nbc: Color(red: 0.0, green: 0.4, blue: 0.8),             // NBC Blue
    RokuAppID.adultSwim: Color(red: 0.0, green: 0.0, blue: 0.0),       // Adult Swim Black
    RokuAppID.discoveryGO: Color(red: 0.0, green: 0.35, blue: 0.65),   // Discovery Blue
    RokuAppID.hgtvGO: Color(red: 0.55, green: 0.78, blue: 0.24),       // HGTV Green
    RokuAppID.dropout: Color(red: 0.98, green: 0.76, blue: 0.0),       // Dropout Yellow
    RokuAppID.vix: Color(red: 0.96, green: 0.49, blue: 0.0),           // ViX Orange

    // Sports
    RokuAppID.espn: Color(red: 0.8, green: 0.0, blue: 0.0),            // ESPN Red
    RokuAppID.nfl: Color(red: 0.0, green: 0.2, blue: 0.45),            // NFL Blue
    RokuAppID.nflSundayTicket: Color(red: 0.0, green: 0.2, blue: 0.45),

    // Kids
    RokuAppID.pbsKids: Color(red: 0.0, green: 0.6, blue: 0.3),         // PBS Green
    RokuAppID.kidsFamily: rokuPurple,

    // System
    RokuAppID.rokuMediaPlayer: rokuPurple,
  ]

  // MARK: - Brand Data by Name (Fallback for unknown IDs)

  private static let abbreviationsByName: [String: String] = [
    "Netflix": "N",
    "Prime Video": "P",
    "Amazon": "P",
    "YouTube": "YT",
    "Hulu": "H",
    "Disney": "D+",
    "HBO": "MAX",
    "Max": "MAX",
    "Peacock": "🦚",
    "Apple TV": "tv",
    "Apple Music": "♫",
    "Paramount": "P+",
    "Spotify": "S",
    "Plex": "▶",
    "Pluto": "P",
    "Tubi": "T",
    "Fandango": "F",
    "Vudu": "F",
    "Crunchyroll": "CR",
    "Roku": "R",
    "ESPN": "ESPN",
    "NFL": "NFL",
    "PBS": "PBS",
  ]

  private static let colorsByName: [String: Color] = [
    "Netflix": Color(red: 0.89, green: 0.09, blue: 0.14),
    "Prime": Color(red: 0.0, green: 0.67, blue: 0.86),
    "Amazon": Color(red: 0.0, green: 0.67, blue: 0.86),
    "YouTube": Color(red: 1.0, green: 0.0, blue: 0.0),
    "Hulu": Color(red: 0.11, green: 0.85, blue: 0.45),
    "Disney": Color(red: 0.07, green: 0.21, blue: 0.55),
    "HBO": Color(red: 0.6, green: 0.0, blue: 1.0),
    "Max": Color(red: 0.0, green: 0.27, blue: 0.82),
    "Peacock": Color(red: 0.0, green: 0.0, blue: 0.0),
    "Apple": Color(red: 0.2, green: 0.2, blue: 0.2),
    "Paramount": Color(red: 0.0, green: 0.35, blue: 0.74),
    "Spotify": Color(red: 0.12, green: 0.84, blue: 0.38),
    "Plex": Color(red: 0.91, green: 0.67, blue: 0.15),
    "Pluto": Color(red: 0.0, green: 0.0, blue: 0.0),
    "Tubi": Color(red: 0.98, green: 0.24, blue: 0.24),
    "Fandango": Color(red: 0.2, green: 0.6, blue: 0.86),
    "Vudu": Color(red: 0.2, green: 0.6, blue: 0.86),
    "Crunchyroll": Color(red: 0.95, green: 0.51, blue: 0.13),
    "Roku": rokuPurple,
    "ESPN": Color(red: 0.8, green: 0.0, blue: 0.0),
    "NFL": Color(red: 0.0, green: 0.2, blue: 0.45),
    "PBS": Color(red: 0.0, green: 0.6, blue: 0.3),
  ]

}
