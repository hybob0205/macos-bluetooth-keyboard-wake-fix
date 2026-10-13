#!/bin/bash
# Optional per-user login startup. Run only after a successful manual trial.
set -euo pipefail
cd "$(dirname "$0")"
label="local.bluetoothkeyboard.wakefix"
domain="gui/$(id -u)"
plist="$HOME/Library/LaunchAgents/$label.plist"
installed="$HOME/Applications/BluetoothKeyboardWakeFix.app"
case "${1:-}" in
    enable)
        test -x build/BluetoothKeyboardWakeFix.app/Contents/MacOS/BluetoothKeyboardWakeFix || {
            printf 'Run bash build.sh first.\n' >&2; exit 1;
        }
        # Preserve an existing installation instead of overwriting a running app.
        if test -e "$installed" || test -e "$plist"; then
            printf 'Existing installation found; run bash login.sh disable, remove or move the old app, then retry.\n' >&2
            exit 1
        fi
        mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
        ditto build/BluetoothKeyboardWakeFix.app "$installed"
        plutil -create xml1 "$plist"
        plutil -insert Label -string "$label" "$plist"
        plutil -insert ProgramArguments -xml '<array/>' "$plist"
        plutil -insert ProgramArguments.0 -string "$installed/Contents/MacOS/BluetoothKeyboardWakeFix" "$plist"
        plutil -insert ProgramArguments.1 -string '--background' "$plist"
        plutil -insert RunAtLoad -bool YES "$plist"
        plutil -insert LimitLoadToSessionType -string Aqua "$plist"
        plutil -lint "$plist"
        launchctl bootstrap "$domain" "$plist"
        printf 'Login startup enabled. Open the installed app to view status.\n'
        ;;
    disable)
        launchctl bootout "$domain/$label" 2>/dev/null || true
        rm -f "$plist"
        printf 'Login startup disabled. Installed app and its settings retained.\n'
        ;;
    *) printf 'Usage: bash login.sh enable|disable\n' >&2; exit 1 ;;
esac
