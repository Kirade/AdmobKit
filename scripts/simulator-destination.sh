#!/bin/bash
# Prints an xcodebuild destination for an available iPhone simulator on the newest iOS runtime,
# so CI and local runs never depend on a hard-coded device name.
set -euo pipefail

xcrun simctl list devices available --json | python3 -c '
import json
import sys

devices = json.load(sys.stdin)["devices"]
runtimes = [r for r in devices if ".SimRuntime.iOS-" in r]
runtimes.sort(key=lambda r: [int(part) for part in r.rsplit("iOS-", 1)[1].split("-")])
for runtime in reversed(runtimes):
    for device in devices[runtime]:
        if device["name"].startswith("iPhone"):
            print("id=" + device["udid"])
            sys.exit(0)
sys.exit("No available iPhone simulator")
'
