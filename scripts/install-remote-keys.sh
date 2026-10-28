#!/usr/bin/env bash
# Installs the Strong remote key remap (scripts/remote/70-strong-remote.hwdb). Needs root once (asks via pkexec).
# Button -> evdev key (Qt name): off F14 (Launch 5), input F15 (Launch 6), mic F16 (Launch 7), gear F17 (Launch 8),
# YouTube F18 (Launch 9), Netflix F19, Prime PROG3 (Launch 3), Disney+ PROG4 (Launch 4), TV PROG1 (Launch 1; not F13, which is Tools = System Settings).
set -euo pipefail
src="$(cd "$(dirname "$0")" && pwd)/remote/70-strong-remote.hwdb"
pkexec sh -c "install -m 0644 '$src' /etc/udev/hwdb.d/70-strong-remote.hwdb && systemd-hwdb update && udevadm trigger --subsystem-match=input --action=change"
echo "installed. Turn the remote off and on (or: bluetoothctl disconnect <mac>, then press a button): keys the remote's input device did not have when it connected (PROG1-4) only work after it reconnects."
