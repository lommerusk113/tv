#!/usr/bin/env bash
# Lets the Bluetooth remote wake the laptop: installs scripts/remote/71-bluetooth-wake.rules into /etc/udev/rules.d
# and switches wakeup on now (pkexec asks for the password once). Undo: sudo rm /etc/udev/rules.d/71-bluetooth-wake.rules
set -euo pipefail
src="$(cd "$(dirname "$0")" && pwd)/remote/71-bluetooth-wake.rules"
bt=""
for d in /sys/bus/usb/devices/*; do
    if [ "$(cat "$d/idVendor" 2>/dev/null)" = "8087" ] && [ "$(cat "$d/idProduct" 2>/dev/null)" = "0033" ]; then
        bt="$d"
    fi
done
[ -n "$bt" ] || { echo "Intel AX211 Bluetooth adapter (8087:0033) not found" >&2; exit 1; }
pkexec sh -c "install -m 0644 '$src' /etc/udev/rules.d/71-bluetooth-wake.rules \
  && echo enabled > '$bt/power/wakeup' && echo enabled > /sys/bus/usb/devices/usb3/power/wakeup"
echo "wake from Bluetooth: adapter $(cat "$bt/power/wakeup"), hub $(cat /sys/bus/usb/devices/usb3/power/wakeup)"
