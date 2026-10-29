#!/bin/sh
# Runs every test: the package on the Mac (swift test), then the app, snapshot and UI tests on the
# iPhone 17e simulator, and prints a short summary.
#
#   scripts/test-all.sh [-only-testing:Target/Class ...]
#
# Xcode's test build sometimes keeps a stale copy of the local package's modules; the package's build
# products are removed first so the simulator run always tests the current code.
set -e
cd "$(dirname "$0")/.."
DEVICE=${DEVICE:-"iPhone 17e"}

echo "== package (Mac)"
(cd Packages/KonstanzKit && swift test 2>&1 | grep -E "✘|error:|Test run with" | head -20)

echo "== app (simulator: $DEVICE)"
rm -rf build/DerivedData/Build/Intermediates.noindex/KonstanzKit.build build/DerivedData/Build/Products/Debug-iphonesimulator/KG*
xcodegen -q
xcodebuild test -scheme KonstanzGo -destination "platform=iOS Simulator,name=$DEVICE" \
    -derivedDataPath build/DerivedData "$@" 2>&1 \
    | grep -E "Fatal|error:|TEST (SUCCEEDED|FAILED)" | grep -v IDESchemeActionSDKRecord | cut -c1-220 | head -20
RESULT=$(ls -td build/DerivedData/Logs/Test/*.xcresult | head -1)
xcrun xcresulttool get test-results summary --path "$RESULT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(d["result"], d["passedTests"], "passed", d["failedTests"], "failed")
for f in d.get("testFailures", []):
    print(" ", f["targetName"], "/", f["testName"], ":", f["failureText"][:200])
'
