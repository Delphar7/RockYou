// AnimationScrubber.swift
// RockYou
//
// Reusable animation timeline control for debug views.
// Provides play/pause, frame stepping, and subframe interpolation.
// macOS-only (excluded from iOS via build settings)

import SwiftUI

/// Reusable animation scrubber for debug views.
///
/// Provides:
/// - Play/Pause toggle
/// - Frame stepping (prev/next)
/// - Coarse timeline slider (frame-level)
/// - Fine subframe slider (interpolation within frame, shown when paused)
///
/// Usage:
/// ```swift
/// @State private var time: Double = 0
/// @State private var subFrame: Double = 0
/// @State private var isPlaying: Bool = false
///
/// AnimationScrubber(
///     timeRange: 0...8.0,
///     frameRate: 60,
///     currentTime: $time,
///     subFrameProgress: $subFrame,
///     isPlaying: $isPlaying
/// )
/// ```
struct AnimationScrubber: View {
  let timeRange: ClosedRange<Double>
  let frameRate: Double
  @Binding var currentTime: Double
  @Binding var subFrameProgress: Double
  @Binding var isPlaying: Bool

  /// Optional callback when animation ticks (called at frameRate when playing)
  var onTick: ((Double) -> Void)?

  @State private var timer: Timer?

  private var frameDuration: Double { 1.0 / frameRate }
  private var totalFrames: Int {
    Int((timeRange.upperBound - timeRange.lowerBound) * frameRate)
  }
  private var currentFrame: Int {
    Int((currentTime - timeRange.lowerBound) * frameRate)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Transport controls + frame display
      HStack(spacing: 8) {
        // Prev frame
        Button(action: stepBackward) {
          Image(systemName: "backward.frame.fill")
        }
        .buttonStyle(.bordered)
        .disabled(currentFrame <= 0)

        // Play/Pause
        Button(action: togglePlayback) {
          Image(systemName: isPlaying ? "pause.fill" : "play.fill")
        }
        .buttonStyle(.bordered)

        // Next frame
        Button(action: stepForward) {
          Image(systemName: "forward.frame.fill")
        }
        .buttonStyle(.bordered)
        .disabled(currentFrame >= totalFrames - 1)

        Spacer()

        // Frame counter
        Text("Frame \(currentFrame)/\(totalFrames)")
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.secondary)
      }

      // Timeline slider (coarse)
      HStack {
        Text(formatTime(timeRange.lowerBound))
          .font(.system(.caption2, design: .monospaced))
          .foregroundStyle(.tertiary)
          .frame(width: 40, alignment: .leading)

        Slider(value: $currentTime, in: timeRange)
          .onChange(of: currentTime) { _, _ in
            // Reset subframe when scrubbing
            if !isPlaying {
              subFrameProgress = 0
            }
          }

        Text(formatTime(timeRange.upperBound))
          .font(.system(.caption2, design: .monospaced))
          .foregroundStyle(.tertiary)
          .frame(width: 40, alignment: .trailing)
      }

      // Subframe slider (fine, shown when paused)
      if !isPlaying {
        HStack {
          Text("Sub")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 40, alignment: .leading)

          Slider(value: $subFrameProgress, in: 0...1)

          Text(String(format: "%.0f%%", subFrameProgress * 100))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: 40, alignment: .trailing)
        }
      }
    }
    .onDisappear {
      stopTimer()
    }
    .onChange(of: isPlaying) { _, playing in
      if playing {
        startTimer()
      } else {
        stopTimer()
      }
    }
  }

  // MARK: - Actions

  private func togglePlayback() {
    isPlaying.toggle()
  }

  private func stepForward() {
    isPlaying = false
    let newTime = min(currentTime + frameDuration, timeRange.upperBound)
    currentTime = newTime
    subFrameProgress = 0
  }

  private func stepBackward() {
    isPlaying = false
    let newTime = max(currentTime - frameDuration, timeRange.lowerBound)
    currentTime = newTime
    subFrameProgress = 0
  }

  // MARK: - Timer

  private func startTimer() {
    stopTimer()
    timer = Timer.scheduledTimer(withTimeInterval: frameDuration, repeats: true) { _ in
      tick()
    }
  }

  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  private func tick() {
    var newTime = currentTime + frameDuration
    if newTime > timeRange.upperBound {
      // Loop back to start
      newTime = timeRange.lowerBound
    }
    currentTime = newTime
    onTick?(newTime)
  }

  // MARK: - Formatting

  private func formatTime(_ time: Double) -> String {
    String(format: "%.2fs", time)
  }
}

// MARK: - Convenience Initializer

extension AnimationScrubber {
  /// Creates a scrubber with default subframe progress (internal state)
  init(
    timeRange: ClosedRange<Double>,
    frameRate: Double = 60,
    currentTime: Binding<Double>,
    isPlaying: Binding<Bool>,
    onTick: ((Double) -> Void)? = nil
  ) {
    self.timeRange = timeRange
    self.frameRate = frameRate
    self._currentTime = currentTime
    self._subFrameProgress = .constant(0)
    self._isPlaying = isPlaying
    self.onTick = onTick
  }
}

// MARK: - Preview

#Preview("Animation Scrubber") {
  struct PreviewWrapper: View {
    @State private var time: Double = 0
    @State private var subFrame: Double = 0
    @State private var isPlaying: Bool = false

    var body: some View {
      VStack(spacing: 20) {
        Text("Current: \(String(format: "%.3f", time)) + \(String(format: "%.2f", subFrame))")
          .font(.system(.title2, design: .monospaced))

        AnimationScrubber(
          timeRange: 0...8.0,
          frameRate: 60,
          currentTime: $time,
          subFrameProgress: $subFrame,
          isPlaying: $isPlaying
        )
      }
      .padding()
      .frame(width: 350)
    }
  }

  return PreviewWrapper()
}
