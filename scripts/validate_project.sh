#!/usr/bin/env bash
set -euo pipefail

required_files=(
  "RenewalLedger.xcodeproj/project.pbxproj"
  "RenewalLedger/Resources/Info.plist"
  "RenewalLedger/Resources/PrivacyInfo.xcprivacy"
  "RenewalLedger/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
  "RenewalLedger/App/RenewalLedgerApp.swift"
  "RenewalLedger/Services/BackgroundImageStore.swift"
  "RenewalLedger/Services/ExchangeRateStore.swift"
  "RenewalLedger/Services/NotificationManager.swift"
  "RenewalLedger/Views/DashboardView.swift"
  "RenewalLedger/Views/SettingsView.swift"
  ".github/workflows/build-release.yml"
  ".release-trigger"
)

for path in "${required_files[@]}"; do
  if [[ ! -e "$path" ]]; then
    echo "Missing required file: $path" >&2
    exit 1
  fi
done

python3 - <<'PY'
import json
import pathlib
import plistlib
import struct
import xml.etree.ElementTree as ET

for path in pathlib.Path("RenewalLedger/Resources/Assets.xcassets").rglob("Contents.json"):
    with path.open("rb") as handle:
        json.load(handle)

with open("RenewalLedger/Resources/Info.plist", "rb") as handle:
    plistlib.load(handle)

with open("RenewalLedger/Resources/PrivacyInfo.xcprivacy", "rb") as handle:
    privacy_manifest = plistlib.load(handle)
if privacy_manifest.get("NSPrivacyTracking") is not False:
    raise SystemExit("Privacy manifest must declare tracking as disabled")

for path in pathlib.Path("Artwork").glob("*.svg"):
    ET.parse(path)

project = pathlib.Path("RenewalLedger.xcodeproj/project.pbxproj").read_text()
for path in pathlib.Path("RenewalLedger").rglob("*.swift"):
    marker = f"{path.name} in Sources"
    marker_count = project.count(marker)
    if marker_count != 2:
        raise SystemExit(
            f"Swift source must appear exactly once in the build phase: {path} "
            f"(marker count: {marker_count})"
        )

if project.count("PrivacyInfo.xcprivacy in Resources") != 2:
    raise SystemExit("PrivacyInfo.xcprivacy must appear exactly once in Resources")

for path in pathlib.Path("RenewalLedger/Resources/Assets.xcassets/AppIcon.appiconset").glob("*.png"):
    with path.open("rb") as handle:
        signature = handle.read(8)
        if signature != b"\x89PNG\r\n\x1a\n":
            raise SystemExit(f"Invalid PNG signature: {path}")
        length = struct.unpack(">I", handle.read(4))[0]
        if handle.read(4) != b"IHDR" or length != 13:
            raise SystemExit(f"Missing PNG IHDR: {path}")
        width, height, bit_depth, color_type, _, _, _ = struct.unpack(">IIBBBBB", handle.read(13))
        if (width, height) != (1024, 1024):
            raise SystemExit(f"App icon must be 1024x1024: {path}")
        if color_type in (4, 6):
            raise SystemExit(f"App icon must not contain an alpha channel: {path}")

for opening, closing in (("{", "}"), ("(", ")")):
    if project.count(opening) != project.count(closing):
        raise SystemExit(f"Unbalanced {opening}{closing} in Xcode project")
PY

grep -q 'IPHONEOS_DEPLOYMENT_TARGET = 26.0;' RenewalLedger.xcodeproj/project.pbxproj
grep -q 'PRODUCT_BUNDLE_IDENTIFIER = com.zongrui.RenewalLedger;' RenewalLedger.xcodeproj/project.pbxproj
grep -q 'workflow_dispatch:' .github/workflows/build-release.yml
grep -q '^  push:$' .github/workflows/build-release.yml
grep -q '^      - .release-trigger$' .github/workflows/build-release.yml
grep -q 'https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml' RenewalLedger/Services/ExchangeRateStore.swift
grep -q 'PhotosPicker' RenewalLedger/Views/SettingsView.swift
grep -q 'allowLateReminder: false' RenewalLedger/Services/NotificationManager.swift
grep -q 'allowLateReminder: true' RenewalLedger/Services/NotificationManager.swift

grep -q 'scheduledOccurrenceTokens' RenewalLedger/Services/NotificationManager.swift

if grep -Eq '^  (pull_request|schedule):' .github/workflows/build-release.yml; then
  echo "Paid build workflow must not run for PRs or schedules." >&2
  exit 1
fi

echo "Project preflight passed."
