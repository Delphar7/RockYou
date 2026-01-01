#!/bin/bash
set -o pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT="$PROJECT_DIR/RockYou.xcodeproj"
DERIVED_DATA_BASE="$PROJECT_DIR/DerivedData"
RUNALL_LOG_ARCHIVE_DIR="$DERIVED_DATA_BASE/Logs/BuildRunall"

RESET_SIM=0
LINT_ONLY=0
LAUNCH_CONSOLE=0
NO_LOG=0
NO_BUILD_LOCK=0
ALWAYS_BUILD=0
BREAK_LOCKS=0
STATUS_LOCKS=0

mkdir -p "$DERIVED_DATA_BASE" "$RUNALL_LOG_ARCHIVE_DIR"

# MARK: - Global watchexec wrapper (must be first)
#
# Usage:
#   ./BuildRunAll.sh --watchexec <rest of command line>
#
# This wrapper MUST be first to avoid ambiguity with other flags and to prevent recursion.
if [ "${1:-}" = "--watchexec" ]; then
    shift
    if [ $# -eq 0 ]; then
        echo "❌ --watchexec requires a command, e.g.:"
        echo "  $0 --watchexec run-all-tmux"
        exit 1
    fi

    # Fail fast for tmux-only commands so we don't start a long-running watchexec just to
    # immediately error on each restart.
    for arg in "$@"; do
        case "$arg" in
            run-all-tmux)
                if [ -z "${TMUX:-}" ]; then
                    echo "❌ Not in tmux. Run run-all-tmux from inside a tmux session."
                    exit 1
                fi
                ;;
        esac
    done

    # Compute a best-effort minimal watch set based on requested targets/commands.
    # (We intentionally ignore flags like --16e/--16pro/--console/--ResetSim here.)
    wants_phone=0
    wants_watch=0
    wants_ipad=0
    wants_mac=0

    for arg in "$@"; do
        case "$arg" in
            iphone|phone|run-phone|run-iphone) wants_phone=1 ;;
            watch|run-watch) wants_watch=1 ;;
            ipad|run-ipad) wants_ipad=1 ;;
            mac|run-mac) wants_mac=1 ;;
            run-all|run-all-tmux|both) wants_phone=1; wants_watch=1 ;;
        esac
    done

    # If we couldn't infer anything (e.g. --lint with no explicit targets),
    # fall back to watching the main source dirs.
    if [ "$wants_phone" -eq 0 ] && [ "$wants_watch" -eq 0 ] && [ "$wants_ipad" -eq 0 ] && [ "$wants_mac" -eq 0 ]; then
        wants_phone=1
        wants_watch=1
        wants_ipad=1
        wants_mac=1
    fi

    WATCH_ARGS=()
    add_watch() { WATCH_ARGS+=("-w" "$1"); }

    add_watch "$PROJECT_DIR/BuildRunAll.sh"
    add_watch "$PROJECT_DIR/RockYou.xcodeproj"
    add_watch "$PROJECT_DIR/Shared"

    if [ "$wants_watch" -eq 1 ]; then
        add_watch "$PROJECT_DIR/RockYou Watch App"
        add_watch "$PROJECT_DIR/RockYou Watch Widgets"
    fi
    if [ "$wants_phone" -eq 1 ] || [ "$wants_ipad" -eq 1 ] || [ "$wants_mac" -eq 1 ]; then
        add_watch "$PROJECT_DIR/RockYou"
        add_watch "$PROJECT_DIR/Resources"
    fi

    cd "$PROJECT_DIR" || exit 1
    exec watchexec -d "5 s" "${WATCH_ARGS[@]}" -r ./BuildRunAll.sh "$@"
fi

# DerivedData / Build outputs
#
# IMPORTANT: We intentionally isolate DerivedData per *platform tag*.
# When iOS+watch builds run concurrently, they can otherwise race while writing to the same
# Products directories (notably the watch app bundle which iOS embeds).
derived_data_root_for() {
    local platform_tag=$1
    echo "$DERIVED_DATA_BASE/$platform_tag"
}

build_products_root_for() {
    local platform_tag=$1
    # With only -derivedDataPath set (no SYMROOT override), products land in:
    #   <derivedDataPath>/Build/Products/<CONFIG>[-sdk]/
    echo "$(derived_data_root_for "$platform_tag")/Build/Products"
}

bundle_dir_for() {
    local platform_tag=$1
    echo "$(derived_data_root_for "$platform_tag")/BuildResults"
}

ensure_platform_dirs() {
    local platform_tag=$1
    local dd
    dd="$(derived_data_root_for "$platform_tag")"
    mkdir -p "$dd" "$(build_products_root_for "$platform_tag")" "$(bundle_dir_for "$platform_tag")"
}

ensure_dir() {
    local dir=$1
    mkdir -p "$dir"
}

# MARK: - Cross-process build locks (for multi-terminal --watchexec workflows)
#
# Problem: `xcodebuild` cannot safely run concurrently when sharing the same -derivedDataPath.
# In this repo, iPhone + iPad builds intentionally share `platform_tag="iossim"`, so two terminals
# running `--watchexec phone` and `--watchexec ipad` can race and produce Xcode build DB locks.
#
# Solution: Use `lockf(1)` advisory file locks (fcntl) so we can safely block/wait without PID-reuse
# false-positives (a common issue with PID-based lockfiles).
lock_root_dir() {
    echo "$DERIVED_DATA_BASE/Locks"
}

lock_file_for_platform_tag() {
    local platform_tag=$1
    echo "$(lock_root_dir)/${platform_tag}.lock"
}

list_lock_files() {
    local dir
    dir="$(lock_root_dir)"
    if [ ! -d "$dir" ]; then
        return 0
    fi
    find "$dir" -maxdepth 1 -type f -name "*.lock" -print | sort
}

lock_holders_pids_for_file() {
    local lock_file=$1
    # `lsof` is the most practical way to see who has the file open (and thus can hold the lock).
    # If `lsof` isn't available, we fall back to "unknown".
    if ! command -v lsof >/dev/null 2>&1; then
        return 2
    fi
    lsof -t -- "$lock_file" 2>/dev/null | sort -u
}

status_locks() {
    local any=0
    local file
    while IFS= read -r file; do
        any=1
        local base
        base="$(basename "$file")"
        local platform_tag="${base%.lock}"

        local pids=""
        pids="$(lock_holders_pids_for_file "$file" 2>/dev/null || true)"
        if [ -z "$pids" ]; then
            echo "🔓 $platform_tag (free)"
            continue
        fi

        echo "🔒 $platform_tag (held)"
        local pid
        while IFS= read -r pid; do
            if [ -z "$pid" ]; then
                continue
            fi
            # Best-effort: show the command line holding the lock file open.
            local cmdline
            cmdline="$(ps -p "$pid" -o command= 2>/dev/null | sed 's/^[[:space:]]*//')"
            if [ -n "$cmdline" ]; then
                echo "  - pid $pid: $cmdline"
            else
                echo "  - pid $pid"
            fi
        done <<<"$pids"
    done < <(list_lock_files)

    if [ "$any" -eq 0 ]; then
        echo "ℹ️  No lock files found (nothing to report)."
    fi
}

break_locks() {
    local dir
    dir="$(lock_root_dir)"
    if [ ! -d "$dir" ]; then
        echo "ℹ️  No lock dir found; nothing to clean."
        return 0
    fi

    local removed=0
    local held=0
    local file
    while IFS= read -r file; do
        local pids=""
        pids="$(lock_holders_pids_for_file "$file" 2>/dev/null || true)"
        if [ -n "$pids" ]; then
            held=1
            continue
        fi
        rm -f -- "$file" 2>/dev/null || true
        removed=$((removed + 1))
    done < <(list_lock_files)

    if [ "$removed" -gt 0 ]; then
        echo "🧹 Removed $removed unused lock file(s)."
    else
        echo "🧹 No unused lock files to remove."
    fi
    if [ "$held" -eq 1 ]; then
        echo "⚠️  Some locks are currently held; fcntl locks cannot be 'broken' safely."
        echo "   Use --status-locks to see the holding PID(s), then terminate the stuck build if needed."
    fi
}

with_platform_lock() {
    local platform_tag=$1
    shift

    if [ "$NO_BUILD_LOCK" -eq 1 ]; then
        "$@"
        return $?
    fi

    # Indicates whether we had to wait for another process to finish a build for this platform tag.
    # Intended to let callers skip redundant rebuilds (default) while still running install/launch.
    LOCK_WAS_CONTENDED=0

    ensure_dir "$(lock_root_dir)"
    local lock_file
    lock_file="$(lock_file_for_platform_tag "$platform_tag")"

    # bash 3.2: no dynamic file descriptors. Use a fixed fd; we never lock concurrently in-process.
    exec 200>"$lock_file"

    # Try once without waiting; if contended, print a friendly message and then block indefinitely.
    if ! lockf -s -t 0 200 2>/dev/null; then
        echo "⏳ Waiting for build lock: $platform_tag"
        LOCK_WAS_CONTENDED=1
        lockf -s 200 2>/dev/null || {
            exec 200>&-
            return 1
        }
    fi

    local rc=0
    "$@"
    rc=$?

    # Release lock by closing fd.
    exec 200>&-
    return $rc
}

# Timestamp intended for natural sorting (lexicographic == chronological).
timestamp_for_filename() {
    date +"%Y-%m-%d_%H-%M-%S"
}

unique_path() {
    local path=$1
    if [ ! -e "$path" ]; then
        echo "$path"
        return 0
    fi
    local base="${path%.*}"
    local ext=""
    if [[ "$path" == *.* ]]; then
        ext=".${path##*.}"
    fi
    local i=1
    while [ -e "${base}_${i}${ext}" ]; do
        i=$((i + 1))
    done
    echo "${base}_${i}${ext}"
}

prune_archives_for_basename() {
    local base_log_name=$1
    ensure_dir "$RUNALL_LOG_ARCHIVE_DIR"

    local -a files
    # bash 3.2 (macOS default) has no `mapfile`.
    while IFS= read -r line; do
        files+=("$line")
    done < <(find "$RUNALL_LOG_ARCHIVE_DIR" -maxdepth 1 -type f -name "*-${base_log_name}" -print | sort)

    local count=${#files[@]}
    if [ "$count" -le 15 ]; then
        return 0
    fi

    local keep=10
    local delete_count=$((count - keep))
    local i=0
    while [ "$i" -lt "$delete_count" ]; do
        rm -f -- "${files[$i]}"
        i=$((i + 1))
    done
}

archive_existing_log_file() {
    local log_path=$1
    if [ ! -e "$log_path" ]; then
        return 0
    fi

    ensure_dir "$RUNALL_LOG_ARCHIVE_DIR"
    local base
    base="$(basename "$log_path")"
    local ts
    ts="$(timestamp_for_filename)"
    local dest="$RUNALL_LOG_ARCHIVE_DIR/${ts}-${base}"
    dest="$(unique_path "$dest")"
    cp -p -- "$log_path" "$dest"

    prune_archives_for_basename "$base"
}

host_arch() {
    uname -m
}

objroot_for() {
    local derived_data_root=$1
    local platform_tag=$2
    echo "$derived_data_root/Intermediates.$(host_arch)-$platform_tag"
}

log_file_for_target() {
    case "$1" in
        phone|iphone) echo "$PROJECT_DIR/iphone.log" ;;
        watch) echo "$PROJECT_DIR/watch.log" ;;
        ipad) echo "$PROJECT_DIR/ipad.log" ;;
        mac) echo "$PROJECT_DIR/mac.log" ;;
        *) echo "" ;;
    esac
}

archive_log_for_target() {
    local target="$1"
    local log_path
    log_path="$(log_file_for_target "$target")"
    if [ -n "$log_path" ]; then
        archive_existing_log_file "$log_path"
    fi
}

run_with_target_log() {
    local target="$1"
    shift
    local log_path
    log_path="$(log_file_for_target "$target")"
    if [ -z "$log_path" ]; then
        "$@"
        return $?
    fi
    if [ "$NO_LOG" -eq 1 ]; then
        "$@"
        return $?
    fi
    archive_existing_log_file "$log_path"
    "$@" 2>&1 | tee "$log_path"
}

run_target_full() {
    local target="$1"
    case "$target" in
        phone)
            open -g -a Simulator
            build_target phone || return 1
            echo "📱 Launching iPhone..."
            launch_sim_console "$IPHONE_SIM" com.jtr.RockYou
            ;;
        watch)
            open -g -a Simulator
            build_target watch || return 1
            echo "⌚ Launching Watch..."
            launch_sim_console "$WATCH_SIM" com.jtr.RockYou.watchkitapp
            ;;
        ipad)
            open -g -a Simulator
            build_target ipad || return 1
            echo "📱 Launching iPad..."
            launch_sim_console "$IPAD_SIM" com.jtr.RockYou
            ;;
        mac)
            build_target mac || return 1
            echo "🖥️  Launching Mac..."
            run_mac
            ;;
        *)
            echo "❌ Unknown target: $target"
            return 1
            ;;
    esac
}

launch_sim_console() {
    local sim_id=$1
    local bundle_id=$2

    # Default behavior: just launch and return (non-blocking).
    # If you want to tail live logs, pass --console.
    if [ "$LAUNCH_CONSOLE" -eq 0 ]; then
        xcrun simctl launch --terminate-running-process "$sim_id" "$bundle_id" >/dev/null
        return 0
    fi

    # When stdout is piped (e.g. run-all uses `... | tee iphone.log`), `simctl launch --console-pty`
    # can detach/terminate early because it isn't attached to a real TTY. Wrap it in `script` to
    # force a pseudo-tty so logs stay connected and the process doesn't get torn down.
    if [ -t 1 ]; then
        xcrun simctl launch --console-pty --terminate-running-process "$sim_id" "$bundle_id"
    else
        # macOS `script` runs: script [-opts] [file [command ...]]
        script -q /dev/null xcrun simctl launch --console-pty --terminate-running-process "$sim_id" "$bundle_id"
    fi
}

# Simulator profiles (paired phone+watch sets)
#
# Note: CoreSimulator pairing is 1:1 (one iPhone ↔ one Watch). To keep a stable "big" and "small"
# watch workflow, we maintain two paired simulator sets and choose between them with flags.
#
# --16pro (legacy default): jtr iPhone 16 Pro + jtr Apple Watch Series 10 46mm
IPHONE_SIM_16PRO="C6E07BE6-0979-4E4A-9C78-EE2793F7B924"
WATCH_SIM_16PRO="ECBF3DBB-F8F9-44B9-B210-90154331C997"
#
# --16e (new default): jtr iPhone 16e (small) + jtr Apple Watch SE 40mm (small)
IPHONE_SIM_16E="34420C9D-76EB-48CB-9E67-BE7EB8E4B53E"
WATCH_SIM_16E="B0A241D6-35D9-4347-9497-52538C59485E"

# Default simulator profile (can be overridden via flags).
SIM_PROFILE="16e"
SIM_PROFILE_FLAG="--16e"

# Active sims (resolved from SIM_PROFILE).
IPHONE_SIM="$IPHONE_SIM_16E"
WATCH_SIM="$WATCH_SIM_16E"

# jtr iPad Pro 11-inch (iOS 17.5)
IPAD_SIM="09F5F302-5F25-4111-B766-B3E5C9072E45"

# Mac destination (avoid ambiguous destination warning by pinning host arch)
MAC_DEST="platform=macOS,arch=$(host_arch)"

# Boot a simulator if not already booted
boot_if_needed() {
    local sim_id=$1
    local name=$2
    local state
    state=$(xcrun simctl list devices | grep "$sim_id" | grep -o "(Booted)" || true)
    if [ -z "$state" ]; then
        echo "🔌 Booting $name..."
        xcrun simctl boot "$sim_id" 2>/dev/null || true
    fi
}

# Options (must come before targets/commands)
while [[ "${1:-}" == --* ]]; do
    case "${1:-}" in
        --watchexec)
            echo "❌ --watchexec must be the first argument."
            exit 1
            ;;
        --no-log|--no-logs|--nolog)
            NO_LOG=1
            shift
            ;;
        --no-lock|--no-build-lock|--nolock)
            NO_BUILD_LOCK=1
            shift
            ;;
        --always-build|--rebuild)
            ALWAYS_BUILD=1
            shift
            ;;
        --status-locks|--locks-status)
            STATUS_LOCKS=1
            shift
            ;;
        --break-locks|--locks-break)
            BREAK_LOCKS=1
            shift
            ;;
        --ResetSim|--reset-sim)
            RESET_SIM=1
            shift
            ;;
        --lint)
            LINT_ONLY=1
            shift
            ;;
        --console)
            LAUNCH_CONSOLE=1
            shift
            ;;
        --16pro)
            SIM_PROFILE="16pro"
            SIM_PROFILE_FLAG="--16pro"
            IPHONE_SIM="$IPHONE_SIM_16PRO"
            WATCH_SIM="$WATCH_SIM_16PRO"
            shift
            ;;
        --16e)
            SIM_PROFILE="16e"
            SIM_PROFILE_FLAG="--16e"
            IPHONE_SIM="$IPHONE_SIM_16E"
            WATCH_SIM="$WATCH_SIM_16E"
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            # Unknown option; stop parsing so normal validation can handle it.
            break
            ;;
    esac
done

if [ "$STATUS_LOCKS" -eq 1 ]; then
    status_locks
    exit 0
fi

if [ "$BREAK_LOCKS" -eq 1 ]; then
    break_locks
    exit 0
fi

# If lint mode is requested with no targets, default to all targets.
if [ "$LINT_ONLY" -eq 1 ] && [ $# -eq 0 ]; then
    set -- iphone ipad watch mac
fi

# Normalize "iphone" → "phone" internally so the rest of the script only handles one iOS target token.
NORMALIZED_ARGS=()
for arg in "$@"; do
    if [ "$arg" = "iphone" ]; then
        NORMALIZED_ARGS+=("phone")
    else
        NORMALIZED_ARGS+=("$arg")
    fi
done
set -- "${NORMALIZED_ARGS[@]}"

maybe_reset_app() {
    local sim_id=$1
    local bundle_id=$2
    if [ "$RESET_SIM" -eq 1 ]; then
        xcrun simctl terminate "$sim_id" "$bundle_id" 2>/dev/null || true
        xcrun simctl uninstall "$sim_id" "$bundle_id" 2>/dev/null || true
    fi
}

# Build iOS app for a simulator (iPhone or iPad)
# Usage: build_ios <sim_id> <name> <bundle_suffix>
build_ios() {
    local sim_id=$1
    local name=$2
    local bundle_suffix=$3
    local platform_tag="iossim"
    ensure_platform_dirs "$platform_tag"
    local derived_data_root
    derived_data_root="$(derived_data_root_for "$platform_tag")"
    local build_products_root
    build_products_root="$(build_products_root_for "$platform_tag")"
    local bundle_dir
    bundle_dir="$(bundle_dir_for "$platform_tag")"
    with_platform_lock "$platform_tag" _build_ios_locked "$sim_id" "$name" "$bundle_suffix" "$derived_data_root" "$bundle_dir"
}

_build_ios_locked() {
    local sim_id=$1
    local name=$2
    local bundle_suffix=$3
    local derived_data_root=$4
    local bundle_dir=$5

    local app_path
    app_path="$(build_products_root_for iossim)/Debug-iphonesimulator/RockYou.app"
    if [ "${LOCK_WAS_CONTENDED:-0}" -eq 1 ] && [ "$ALWAYS_BUILD" -eq 0 ] && [ -d "$app_path" ]; then
        echo "✅ Skipping $name build (another process already built iossim)"
        return 0
    fi

    echo "📱 Building $name app..."
    rm -rf "$bundle_dir/RockYou$bundle_suffix" "$bundle_dir/RockYou$bundle_suffix.xcresult"
    xcodebuild -scheme RockYou -configuration Debug \
        -project "$PROJECT" \
        -derivedDataPath "$derived_data_root" \
        -destination "platform=iOS Simulator,id=$sim_id" \
        -resultBundlePath "$bundle_dir/RockYou$bundle_suffix.xcresult" \
        -allowProvisioningUpdates build | xcbeautify
}

build_watch() {
    local platform_tag="watchsim"
    ensure_platform_dirs "$platform_tag"
    local derived_data_root
    derived_data_root="$(derived_data_root_for "$platform_tag")"
    local build_products_root
    build_products_root="$(build_products_root_for "$platform_tag")"
    local bundle_dir
    bundle_dir="$(bundle_dir_for "$platform_tag")"
    with_platform_lock "$platform_tag" _build_watch_locked "$WATCH_SIM" "$derived_data_root" "$bundle_dir"
}

_build_watch_locked() {
    local watch_sim_id=$1
    local derived_data_root=$2
    local bundle_dir=$3

    local app_path
    app_path="$(build_products_root_for watchsim)/Debug-watchsimulator/RockYou Watch App.app"
    if [ "${LOCK_WAS_CONTENDED:-0}" -eq 1 ] && [ "$ALWAYS_BUILD" -eq 0 ] && [ -d "$app_path" ]; then
        echo "✅ Skipping Watch build (another process already built watchsim)"
        return 0
    fi

    echo "⌚ Building Watch app..."
    rm -rf "$bundle_dir/RockYou Watch App" "$bundle_dir/RockYou Watch App.xcresult"
    xcodebuild -scheme 'RockYou Watch App' -configuration Debug \
        -project "$PROJECT" \
        -derivedDataPath "$derived_data_root" \
        -destination "platform=watchOS Simulator,id=$watch_sim_id" \
        -resultBundlePath "$bundle_dir/RockYou Watch App.xcresult" \
        -allowProvisioningUpdates build | xcbeautify
}

build_mac() {
    local platform_tag="macos"
    ensure_platform_dirs "$platform_tag"
    local derived_data_root
    derived_data_root="$(derived_data_root_for "$platform_tag")"
    local build_products_root
    build_products_root="$(build_products_root_for "$platform_tag")"
    local bundle_dir
    bundle_dir="$(bundle_dir_for "$platform_tag")"
    with_platform_lock "$platform_tag" _build_mac_locked "$derived_data_root" "$bundle_dir"
}

_build_mac_locked() {
    local derived_data_root=$1
    local bundle_dir=$2

    local app_path
    app_path="$(build_products_root_for macos)/Debug/RockYou.app"
    if [ "${LOCK_WAS_CONTENDED:-0}" -eq 1 ] && [ "$ALWAYS_BUILD" -eq 0 ] && [ -d "$app_path" ]; then
        echo "✅ Skipping Mac build (another process already built macos)"
        return 0
    fi

    echo "🖥️  Building Mac app..."
    rm -rf "$bundle_dir/RockYou-Mac" "$bundle_dir/RockYou-Mac.xcresult"
    xcodebuild -scheme RockYou -configuration Debug \
        -project "$PROJECT" \
        -derivedDataPath "$derived_data_root" \
        -destination "$MAC_DEST" \
        -resultBundlePath "$bundle_dir/RockYou-Mac.xcresult" \
        -allowProvisioningUpdates build | xcbeautify
}

# Run iOS app on a simulator (iPhone or iPad)
# Usage: run_ios <sim_id> <name>
run_ios() {
    local sim_id=$1
    local name=$2
    echo "📱 Installing and launching $name app..."
    maybe_reset_app "$sim_id" com.jtr.RockYou
    xcrun simctl install "$sim_id" "$(build_products_root_for iossim)/Debug-iphonesimulator/RockYou.app"
    launch_sim_console "$sim_id" com.jtr.RockYou
}

run_watch() {
    echo "⌚ Installing and launching Watch app..."
    maybe_reset_app "$WATCH_SIM" com.jtr.RockYou.watchkitapp
    xcrun simctl install "$WATCH_SIM" "$(build_products_root_for watchsim)/Debug-watchsimulator/RockYou Watch App.app"
    launch_sim_console "$WATCH_SIM" com.jtr.RockYou.watchkitapp
}

run_mac() {
    echo "🖥️  Launching Mac app..."
    # Kill existing *macOS* instance if running.
    # NOTE: The iOS Simulator app process is also named "RockYou", so `pkill -x RockYou`
    # would kill the simulator app too. Match the macOS binary path instead.
    local mac_bin="$(build_products_root_for macos)/Debug/RockYou.app/Contents/MacOS/RockYou"
    pkill -f "$mac_bin" 2>/dev/null || true
    sleep 0.5
    "$mac_bin"
    # Tail the system log for our app
    #log stream --predicate 'subsystem == "com.jtr.RockYou" OR process == "RockYou"' --style compact
}

# Build and install a single target (no launch)
build_target() {
    local target=$1
    case "$target" in
        phone)
            boot_if_needed "$IPHONE_SIM" "iPhone"
            build_ios "$IPHONE_SIM" "iPhone" "" || return 1
            maybe_reset_app "$IPHONE_SIM" com.jtr.RockYou
            xcrun simctl install "$IPHONE_SIM" "$(build_products_root_for iossim)/Debug-iphonesimulator/RockYou.app"
            ;;
        watch)
            boot_if_needed "$WATCH_SIM" "Watch"
            build_watch || return 1
            maybe_reset_app "$WATCH_SIM" com.jtr.RockYou.watchkitapp
            xcrun simctl install "$WATCH_SIM" "$(build_products_root_for watchsim)/Debug-watchsimulator/RockYou Watch App.app"
            ;;
        ipad)
            boot_if_needed "$IPAD_SIM" "iPad"
            build_ios "$IPAD_SIM" "iPad" "-iPad" || return 1
            maybe_reset_app "$IPAD_SIM" com.jtr.RockYou
            xcrun simctl install "$IPAD_SIM" "$(build_products_root_for iossim)/Debug-iphonesimulator/RockYou.app"
            ;;
        mac)
            build_mac || return 1
            ;;
        *)
            echo "❌ Unknown target: $target"
            return 1
            ;;
    esac
}

# Build only (no install/launch). Intended for quick "lint" compile checks.
lint_target() {
    local target=$1
    case "$target" in
        phone)
            build_ios "$IPHONE_SIM" "iPhone" "" || return 1
            ;;
        watch)
            build_watch || return 1
            ;;
        ipad)
            build_ios "$IPAD_SIM" "iPad" "-iPad" || return 1
            ;;
        mac)
            build_mac || return 1
            ;;
        *)
            echo "❌ Unknown target: $target"
            return 1
            ;;
    esac
}
# Check if target is valid
is_valid_target() {
    case "$1" in
        phone|iphone|watch|ipad|mac) return 0 ;;
        *) return 1 ;;
    esac
}

# Handle single command or multiple targets
if [ $# -eq 0 ]; then
    echo "Usage: $0 <target> [target...]"
    echo ""
    echo "Options:"
    echo "  --watchexec - Must be first. Re-run this command on changes via watchexec."
    echo "  --16e       - Use jtr iPhone 16e (small) + Watch SE 40mm (small) (default)"
    echo "  --16pro     - Use jtr iPhone 16 Pro + Watch Series 10 46mm"
    echo "  --ResetSim  - Terminate+uninstall before install (slower; fixes some sim launch flakiness)"
    echo "  --lint      - Build only (no install/launch). If no targets given, builds phone+ipad+watch+mac."
    echo "  --console   - Keep streaming simulator console output (blocks; useful in tmux panes)"
    echo "  --no-log    - Disable tee-to-log (intended for tmux mode where tmux pipe-pane handles logs)"
    echo "  --no-lock   - Disable cross-process DerivedData locks (not recommended; can cause Xcode build DB lock errors)"
    echo "  --always-build - Rebuild even if we had to wait on a concurrent build lock"
    echo "  --status-locks - Show any currently held build locks (best-effort via lsof)"
    echo "  --break-locks  - Remove unused lock files (does not kill running builds)"
    echo ""
    echo "Targets (can combine multiple):"
    echo "  iphone     - iPhone app (alias: phone)"
    echo "  phone      - iPhone app (alias: iphone)"
    echo "  watch      - Watch app"
    echo "  ipad       - iPad app"
    echo "  mac        - Mac app"
    echo ""
    echo "Special commands:"
    echo "  run-all    - Build and run phone+watch (no tmux required)"
    echo "  run-all-tmux - Build and run phone+watch in tmux (console streaming)"
    echo "  both       - Alias for 'phone watch'"
    echo "  run-phone  - Just launch iPhone (skip build)"
    echo "  run-watch  - Just launch Watch (skip build)"
    echo "  run-ipad   - Just launch iPad (skip build)"
    echo "  run-mac    - Just launch Mac (skip build)"
    echo "  boot       - Just boot phone+watch simulators"
    echo "  status     - Show simulator and pairing status"
    echo ""
    echo "Examples:"
    echo "  $0 phone              # Build and run iPhone"
    echo "  $0 phone ipad         # Build and run iPhone + iPad"
    echo "  $0 phone watch mac    # Build and run all three"
    echo "  $0 --lint             # Build-only lint pass for phone+ipad+watch+mac"
    echo ""
    echo "Logs: iphone.log, watch.log, ipad.log, mac.log"
    exit 1
fi

# Check if first arg is a special command
case "$1" in
    run-all)
        if [ "$LINT_ONLY" -eq 1 ]; then
            echo "❌ --lint is not compatible with run-all"
            exit 1
        fi
        # Simple semantics: build + launch phone and watch. No tmux required.
        exec "$0" "$SIM_PROFILE_FLAG" phone watch
        ;;

    run-all-tmux)
        if [ "$LINT_ONLY" -eq 1 ]; then
            echo "❌ --lint is not compatible with run-all-tmux"
            exit 1
        fi
        if [ -z "$TMUX" ]; then
            echo "❌ Not in tmux. Run run-all-tmux from inside a tmux session."
            exit 1
        fi

        RUNALL_WIN="RockYou-runall"
        # Keep a stable window/pane layout across reruns (especially under watchexec).
        #
        # Important:
        # - tmux can auto-rename windows based on the running command; if that happens, we still
        #   want to find and re-use the existing runall window (instead of creating a new one).
        # - A build failure exits the pane command. Without remain-on-exit, tmux may destroy panes
        #   (and eventually the whole window). We explicitly keep panes/windows around.

        RUNALL_WIN_TGT=""
        if tmux list-windows -F '#{window_name}' | grep -qx "$RUNALL_WIN"; then
            RUNALL_WIN_TGT="$RUNALL_WIN"
        else
            # Best-effort recovery: if tmux auto-renamed the window, locate it by our pane titles.
            RUNALL_WIN_TGT="$(tmux list-panes -a -F '#{window_id} #{pane_title}' | awk '$2 == "runall-watch-pane" || $2 == "runall-phone-pane" { print $1; exit }')"
            if [ -n "$RUNALL_WIN_TGT" ]; then
                tmux rename-window -t "$RUNALL_WIN_TGT" "$RUNALL_WIN" 2>/dev/null || true
            else
                tmux new-window -d -n "$RUNALL_WIN"
                RUNALL_WIN_TGT="$RUNALL_WIN"
            fi
        fi

        # Ensure this window never auto-renames and never disappears when the build command exits.
        tmux set-option -t "$RUNALL_WIN_TGT" automatic-rename off 2>/dev/null || true
        tmux set-option -t "$RUNALL_WIN_TGT" allow-rename off 2>/dev/null || true
        tmux set-option -t "$RUNALL_WIN_TGT" remain-on-exit on 2>/dev/null || true
        tmux set-option -t "$RUNALL_WIN_TGT" monitor-activity on 2>/dev/null || true

        # Ensure exactly 2 panes (0 and 1) in that window.
        PANE_COUNT="$(tmux list-panes -t "$RUNALL_WIN_TGT" | wc -l | tr -d ' ')"
        if [ "$PANE_COUNT" -lt 2 ]; then
            tmux split-window -t "$RUNALL_WIN_TGT" -h
        elif [ "$PANE_COUNT" -gt 2 ]; then
            # Trim any extra panes (keep 0 and 1).
            tmux list-panes -t "$RUNALL_WIN_TGT" -F '#{pane_index} #{pane_id}' \
              | awk '$1 >= 2 { print $2 }' \
              | while read -r pane_id; do
                    tmux kill-pane -t "$pane_id" 2>/dev/null || true
                done
        fi

        # Normalize layout and name the panes for clarity.
        tmux select-layout -t "$RUNALL_WIN_TGT" even-horizontal
        tmux select-pane -t "${RUNALL_WIN_TGT}.0" -T "runall-watch-pane"
        tmux select-pane -t "${RUNALL_WIN_TGT}.1" -T "runall-phone-pane"

        WATCH_PANE="${RUNALL_WIN_TGT}.0"
        PHONE_PANE="${RUNALL_WIN_TGT}.1"

        echo "🚀 Starting both apps in tmux window '$RUNALL_WIN'..."

        boot_if_needed "$IPHONE_SIM" "iPhone"
        boot_if_needed "$WATCH_SIM" "Watch"
        open -g -a Simulator

        # Ensure pane output stays *TTY* (no shell piping), while still capturing logs to files.
        # This avoids `simctl launch --console-pty` flakiness and keeps interactive output readable.
        WATCH_LOG="$PROJECT_DIR/watch.log"
        PHONE_LOG="$PROJECT_DIR/iphone.log"
        archive_existing_log_file "$WATCH_LOG"
        archive_existing_log_file "$PHONE_LOG"
        : >"$WATCH_LOG"
        : >"$PHONE_LOG"

        # Replace any existing commands in-place (no pane accumulation).
        tmux respawn-pane -k -t "$WATCH_PANE" \
          "$PROJECT_DIR/BuildRunAll.sh $SIM_PROFILE_FLAG --no-log --console watch"
        tmux respawn-pane -k -t "$PHONE_PANE" \
          "$PROJECT_DIR/BuildRunAll.sh $SIM_PROFILE_FLAG --no-log --console iphone"

        # Reset and reattach tmux pipes on each run (especially under watchexec).
        # Attach AFTER respawn so we also capture the very start of the build output.
        tmux pipe-pane -t "$WATCH_PANE" 2>/dev/null || true
        tmux pipe-pane -t "$PHONE_PANE" 2>/dev/null || true
        # shellcheck disable=SC2086
        tmux pipe-pane -t "$WATCH_PANE" "cat >> $(printf "%q" "$WATCH_LOG")"
        # shellcheck disable=SC2086
        tmux pipe-pane -t "$PHONE_PANE" "cat >> $(printf "%q" "$PHONE_LOG")"

        # Visually activate the run-all window when we (re)launch it.
        tmux select-window -t "$RUNALL_WIN_TGT" 2>/dev/null || true

        echo "✅ run-all-tmux launched both (watch: $WATCH_PANE, phone: $PHONE_PANE)."
        exit 0
        ;;

    both)
        if [ "$LINT_ONLY" -eq 1 ]; then
            echo "❌ --lint is not compatible with 'both' (use: --lint phone watch)"
            exit 1
        fi
        # Alias for phone watch
        exec "$0" "$SIM_PROFILE_FLAG" phone watch
        ;;

    run-phone)
        if [ "$LINT_ONLY" -eq 1 ]; then
            echo "❌ --lint is not compatible with run-phone"
            exit 1
        fi
        run_with_target_log iphone run_ios "$IPHONE_SIM" "iPhone"
        ;;
    run-iphone)
        if [ "$LINT_ONLY" -eq 1 ]; then
            echo "❌ --lint is not compatible with run-iphone"
            exit 1
        fi
        run_with_target_log iphone run_ios "$IPHONE_SIM" "iPhone"
        ;;

    run-watch)
        if [ "$LINT_ONLY" -eq 1 ]; then
            echo "❌ --lint is not compatible with run-watch"
            exit 1
        fi
        run_with_target_log watch run_watch
        ;;

    run-ipad)
        if [ "$LINT_ONLY" -eq 1 ]; then
            echo "❌ --lint is not compatible with run-ipad"
            exit 1
        fi
        boot_if_needed "$IPAD_SIM" "iPad"
        open -g -a Simulator
        run_with_target_log ipad run_ios "$IPAD_SIM" "iPad"
        ;;

    run-mac)
        if [ "$LINT_ONLY" -eq 1 ]; then
            echo "❌ --lint is not compatible with run-mac"
            exit 1
        fi
        run_with_target_log mac run_mac
        ;;

    boot)
        if [ "$LINT_ONLY" -eq 1 ]; then
            echo "❌ --lint is not compatible with boot"
            exit 1
        fi
        boot_if_needed "$IPHONE_SIM" "iPhone"
        boot_if_needed "$WATCH_SIM" "Watch"
        open -a Simulator
        echo "✅ Both simulators booted"
        ;;

    status)
        if [ "$LINT_ONLY" -eq 1 ]; then
            echo "❌ --lint is not compatible with status"
            exit 1
        fi
        echo "📱 Active sim profile: $SIM_PROFILE ($SIM_PROFILE_FLAG)"
        echo "📊 Simulator status:"
        xcrun simctl list devices | grep -E "(${IPHONE_SIM}|${WATCH_SIM}|${IPAD_SIM})"
        echo ""
        echo "🔗 Pairing status:"
        xcrun simctl list pairs | grep -A2 "$WATCH_SIM" | head -4
        ;;

    *)
        # Lint mode: build only, no install/launch. Default targets if none provided.
        if [ "$LINT_ONLY" -eq 1 ]; then
            if [ $# -eq 0 ]; then
                set -- phone ipad watch mac
            fi

            # Validate targets
            for target in "$@"; do
                if ! is_valid_target "$target"; then
                    echo "❌ Unknown target: $target"
                    echo "Run '$0' without arguments for usage."
                    exit 1
                fi
            done

            echo "🧹 Lint (compile-check) for ${#@} target(s): $*"
            for target in "$@"; do
                lint_target "$target" || exit 1
            done
            echo "✅ Lint (compile-check) succeeded!"
            exit 0
        fi

        # Check if all args are valid targets
        for target in "$@"; do
            if ! is_valid_target "$target"; then
                echo "❌ Unknown command or target: $target"
                echo "Run '$0' without arguments for usage."
                exit 1
            fi
        done

        if [ "$LAUNCH_CONSOLE" -eq 1 ] && [ $# -gt 1 ]; then
            echo "❌ --console is only supported for a single target."
            echo "   Use run-all-tmux for dual-pane console streaming."
            exit 1
        fi

        # Single target: tee the *entire* run (build+install+launch), so --console output is captured.
        if [ $# -eq 1 ]; then
            run_with_target_log "$1" run_target_full "$1"
            exit $?
        fi

        # Multiple targets - build all, then run all
        echo "🚀 Building ${#@} target(s): $*"

        # Open Simulator if any target needs it
        for target in "$@"; do
            if [ "$target" != "mac" ]; then
                open -g -a Simulator
                break
            fi
        done

        # Build and install all targets
        for target in "$@"; do
            run_with_target_log "$target" build_target "$target" || exit 1
        done

        echo ""
        echo "✅ All targets built and installed!"
        echo ""
        echo "Launching..."

        # Launch all targets (mac last since it takes over terminal)
        HAS_MAC=false
        for target in "$@"; do
            case "$target" in
                phone)
                    echo "📱 Launching iPhone..."
                    launch_sim_console "$IPHONE_SIM" com.jtr.RockYou &
                    ;;
                watch)
                    echo "⌚ Launching Watch..."
                    launch_sim_console "$WATCH_SIM" com.jtr.RockYou.watchkitapp &
                    ;;
                ipad)
                    echo "📱 Launching iPad..."
                    launch_sim_console "$IPAD_SIM" com.jtr.RockYou &
                    ;;
                mac)
                    HAS_MAC=true
                    ;;
            esac
        done

        # Wait for simulator launches
        wait

        # Mac last (takes over terminal)
        if [ "$HAS_MAC" = true ]; then
            echo "🖥️  Launching Mac..."
            run_with_target_log mac run_mac
        else
            echo ""
            echo "✅ All apps launched!"
        fi
        ;;
esac
