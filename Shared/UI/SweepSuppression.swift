//
//  SweepSuppression.swift
//  RockYou (Shared)
//
//  Environment flag used to suppress sweep/tap tooltip side-effects while a parent
//  scroll gesture is active (e.g., AppStrip scrolling).
//

import SwiftUI

// NOTE:
// The `sweepSuppressed` EnvironmentKey is now defined in `SweepableModifier.swift`
// to ensure it is always available wherever `.sweepable` is used.
