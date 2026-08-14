#!/usr/bin/env bash
set -euo pipefail

required_files=(
  "RenewalLedger.xcodeproj/project.pbxproj"
  "RenewalLedger/Resources/Info.plist"
  "RenewalLedger/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
  "RenewalLedger/App/RenewalLedgerApp.swift"
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

for path in pathlib.Path("Artwork").glob("*.svg"):
    ET.parse(path)

project = pathlib.Path("RenewalLedger.xcodeproj/project.pbxproj").read_text()
for path in pathlib.Path("RenewalLedger").rglob("*.swift"):
    marker = f"{path.name} in Sources"
    if marker not in project:
        raise SystemExit(f"Swift source is missing from build phase: {path}")

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

if grep -Eq '^  (pull_request|schedule):' .github/workflows/build-release.yml; then
  echo "Paid build workflow must not run for PRs or schedules." >&2
  exit 1
fi

echo "Project preflight passed."
