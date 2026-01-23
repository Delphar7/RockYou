# RockYou Project Guidelines

## Build Commands

**Always use the project build script instead of xcodebuild directly:**

```bash
# Lint/build check for macOS
./BuildRunAll.sh --lint mac

# Other targets
./BuildRunAll.sh --lint iphone
./BuildRunAll.sh --lint ipad
./BuildRunAll.sh --lint watch
```

## Project Structure

- `RockYou/` - Main iOS/macOS app
- `RockYou/UI/Debug/` - macOS-only debug views and harnesses
- `RockYou/UI/Debug/Playground/` - Experimental engines (move to `UI/` when ready)
- `Shared/` - Code shared across all targets
- `Shared/Platform/` - Platform-specific implementations

## Logging

- Use `Log.debug/info/warn/error()` from `Shared/Log.swift`
- `Log.noisy()` is for verbose protocol dumps - disabled by default
- Enable noisy logging only when debugging: `Log.noisyEnabled = true`
