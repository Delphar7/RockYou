#!/bin/bash
set -o pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT="$PROJECT_DIR/RockYou.xcodeproj"
DERIVED_DATA_BASE="$PROJECT_DIR/DerivedData"
RUNALL_LOG_ARCHIVE_DIR="$DERIVED_DATA_BASE/Logs/BuildRunall"

RESET_SIM=0
LINT_ONLY=0

mkdir -p "$DERIVED_DATA_BASE" "$RUNALL_LOG_ARCHIVE_DIR"

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
    mapfile -t files < <(find "$RUNALL_LOG_ARCHIVE_DIR" -maxdepth 1 -type f -name "*-${base_log_name}" -print | sort)

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

launch_sim_console() {
    local sim_id=$1
    local bundle_id=$2

    # When stdout is piped (e.g. run-all uses `... | tee phone.log`), `simctl launch --console-pty`
    # can detach/terminate early because it isn't attached to a real TTY. Wrap it in `script` to
    # force a pseudo-tty so logs stay connected and the process doesn't get torn down.
    if [ -t 1 ]; then
        xcrun simctl launch --console-pty --terminate-running-process "$sim_id" "$bundle_id"
    else
        # macOS `script` runs: script [-opts] [file [command ...]]
        script -q /dev/null xcrun simctl launch --console-pty --terminate-running-process "$sim_id" "$bundle_id"
    fi
}

# jtr iPhone 16 Pro (iOS 26.2) + jtr Apple Watch Series 10 46mm (watchOS 26.2)
IPHONE_SIM="C6E07BE6-0979-4E4A-9C78-EE2793F7B924"
WATCH_SIM="ECBF3DBB-F8F9-44B9-B210-90154331C997"

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

# Option: --ResetSim (terminate + uninstall before install)
while [[ "${1:-}" == "--ResetSim" || "${1:-}" == "--reset-sim" ]]; do
    RESET_SIM=1
    shift
done

# Option: --lint (build only; no install/launch)
while [[ "${1:-}" == "--lint" ]]; do
    LINT_ONLY=1
    shift
done

# If lint mode is requested with no targets, default to all targets.
if [ "$LINT_ONLY" -eq 1 ] && [ $# -eq 0 ]; then
    set -- phone ipad watch mac
fi

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
    echo "📱 Building $name app..."
    rm -rf "$bundle_dir/RockYou$bundle_suffix" "$bundle_dir/RockYou$bundle_suffix.xcresult"
    xcodebuild -scheme RockYou -configuration Debug \
        -project "$PROJECT" \
        -derivedDataPath "$derived_data_root" \
        -destination "platform=iOS Simulator,id=$sim_id" \
        -resultBundlePath "$bundle_dir/RockYou$bundle_suffix.xcresult" \
        -allowProvisioningUpdates build | xcbeautify || return 1
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
    echo "⌚ Building Watch app..."
    rm -rf "$bundle_dir/RockYou Watch App" "$bundle_dir/RockYou Watch App.xcresult"
    xcodebuild -scheme 'RockYou Watch App' -configuration Debug \
        -project "$PROJECT" \
        -derivedDataPath "$derived_data_root" \
        -destination "platform=watchOS Simulator,id=$WATCH_SIM" \
        -resultBundlePath "$bundle_dir/RockYou Watch App.xcresult" \
        -allowProvisioningUpdates build | xcbeautify || return 1
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
    echo "🖥️  Building Mac app..."
    rm -rf "$bundle_dir/RockYou-Mac" "$bundle_dir/RockYou-Mac.xcresult"
    xcodebuild -scheme RockYou -configuration Debug \
        -project "$PROJECT" \
        -derivedDataPath "$derived_data_root" \
        -destination "$MAC_DEST" \
        -resultBundlePath "$bundle_dir/RockYou-Mac.xcresult" \
        -allowProvisioningUpdates build | xcbeautify || return 1
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
    local mac_log="$PROJECT_DIR/mac.log"
    archive_existing_log_file "$mac_log"
    "$mac_bin" 2>&1 | tee "$mac_log"
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
        phone|watch|ipad|mac) return 0 ;;
        *) return 1 ;;
    esac
}

# Handle single command or multiple targets
if [ $# -eq 0 ]; then
    echo "Usage: $0 <target> [target...]"
    echo ""
    echo "Options:"
    echo "  --ResetSim  - Terminate+uninstall before install (slower; fixes some sim launch flakiness)"
    echo "  --lint      - Build only (no install/launch). If no targets given, builds phone+ipad+watch+mac."
    echo ""
    echo "Targets (can combine multiple):"
    echo "  phone      - iPhone app"
    echo "  watch      - Watch app"
    echo "  ipad       - iPad app"
    echo "  mac        - Mac app"
    echo ""
    echo "Special commands:"
    echo "  run-all    - Build and run phone+watch in tmux (phone in pane 1, watch in pane 0)"
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
    echo "Logs: phone.log, watch.log (when using run-all)"
    exit 1
fi

# Check if first arg is a special command
case "$1" in
    run-all)
        if [ "$LINT_ONLY" -eq 1 ]; then
            echo "❌ --lint is not compatible with run-all"
            exit 1
        fi
        # Ensure we're in tmux
        if [ -z "$TMUX" ]; then
            echo "❌ Not in tmux. Run this from inside a tmux session."
            exit 1
        fi

        # Check pane 1 exists
        if ! tmux list-panes -F '#{pane_index}' | grep -q '^1$'; then
            echo "❌ Pane 1 doesn't exist. Split your tmux window first (Ctrl-b %)"
            exit 1
        fi

        echo "🚀 Starting both apps..."

        # Boot simulators first
        boot_if_needed "$IPHONE_SIM" "iPhone"
        boot_if_needed "$WATCH_SIM" "Watch"
        open -g -a Simulator

        # Kill any running process in pane 1
        tmux send-keys -t ".1" C-c
        sleep 1

        # Archive existing logs before overwriting them via tee
        archive_existing_log_file "$PROJECT_DIR/phone.log"
        archive_existing_log_file "$PROJECT_DIR/watch.log"

        # Start phone in pane 1 with logging
        tmux send-keys -t ".1" "./BuildRunAll.sh phone 2>&1 | tee phone.log" Enter

        # Wait for phone to build and start
        sleep 4

        # Run watch in current pane with logging
        echo "⌚ Starting Watch app in this pane..."
        exec ./BuildRunAll.sh watch 2>&1 | tee watch.log
        ;;

    both)
        if [ "$LINT_ONLY" -eq 1 ]; then
            echo "❌ --lint is not compatible with 'both' (use: --lint phone watch)"
            exit 1
        fi
        # Alias for phone watch
        exec "$0" phone watch
        ;;

    run-phone)
        if [ "$LINT_ONLY" -eq 1 ]; then
            echo "❌ --lint is not compatible with run-phone"
            exit 1
        fi
        run_ios "$IPHONE_SIM" "iPhone"
        ;;

    run-watch)
        if [ "$LINT_ONLY" -eq 1 ]; then
            echo "❌ --lint is not compatible with run-watch"
            exit 1
        fi
        run_watch
        ;;

    run-ipad)
        if [ "$LINT_ONLY" -eq 1 ]; then
            echo "❌ --lint is not compatible with run-ipad"
            exit 1
        fi
        boot_if_needed "$IPAD_SIM" "iPad"
        open -g -a Simulator
        run_ios "$IPAD_SIM" "iPad"
        ;;

    run-mac)
        if [ "$LINT_ONLY" -eq 1 ]; then
            echo "❌ --lint is not compatible with run-mac"
            exit 1
        fi
        run_mac
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
            build_target "$target" || exit 1
        done

        echo ""
        echo "✅ All targets built and installed!"
        echo ""
        echo "Launching..."

        # Launch all targets (mac last since it takes over terminal with log stream)
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
            run_mac
        else
            echo ""
            echo "✅ All apps launched!"
        fi
        ;;
esac
