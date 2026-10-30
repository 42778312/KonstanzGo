#!/bin/bash
# Checks before uploading to the App Store: a Release build for devices, what Apple reviews in the bundle
# (version, permission texts, privacy manifests, icon, no debug switches), translations and lint.
# Usage: scripts/appstore-check.sh   (prints PASS / WARN / FAIL lines; exits 1 if anything failed)
cd "$(dirname "$0")/.." || exit 1
fails=0
pass() { echo "PASS  $1"; }
warn() { echo "WARN  $1"; }
fail() { echo "FAIL  $1"; fails=$((fails + 1)); }

echo "== Release build (generic iOS device, unsigned)"
if xcodebuild build -scheme KonstanzGo -configuration Release -destination "generic/platform=iOS" \
    -derivedDataPath build/ReleaseCheck CODE_SIGNING_ALLOWED=NO >build/release-check.log 2>&1; then
    pass "Release build"
else
    fail "Release build (see build/release-check.log)"; grep -m5 " error:" build/release-check.log
fi
APP=build/ReleaseCheck/Build/Products/Release-iphoneos/KonstanzGo.app
PLIST="$APP/Info.plist"
[ -d "$APP" ] || { echo "no app bundle, stopping"; exit 1; }

echo "== Info.plist"
get() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null; }
version=$(get CFBundleShortVersionString); build=$(get CFBundleVersion)
[ -n "$version" ] && pass "version $version (build $build)" || fail "no CFBundleShortVersionString"
[ "$(get CFBundleIdentifier)" = "de.konstanzgo.app" ] && pass "bundle id de.konstanzgo.app" || fail "bundle id $(get CFBundleIdentifier)"
for key in NSLocationWhenInUseUsageDescription NSMicrophoneUsageDescription NSSpeechRecognitionUsageDescription; do
    [ -n "$(get $key)" ] && pass "$key" || fail "$key missing"
done
# Background location without a feature that needs it is rejected (guideline 2.5.4).
[ -z "$(get UIBackgroundModes)" ] && pass "no background modes" || fail "UIBackgroundModes set: $(get UIBackgroundModes | tr -d '\n')"
[ -z "$(get NSLocationAlwaysAndWhenInUseUsageDescription)" ] && pass "no unused Always-location text" \
    || warn "Always-location text present but the app never asks for Always"
[ "$(get UIUserInterfaceStyle)" = "Dark" ] && pass "always dark" || warn "UIUserInterfaceStyle not Dark"
[ -z "$(get NSAppTransportSecurity:NSAllowsArbitraryLoads)" ] && pass "no arbitrary network loads" || fail "NSAllowsArbitraryLoads set"
get ITSAppUsesNonExemptEncryption >/dev/null && pass "export compliance key set" \
    || warn "ITSAppUsesNonExemptEncryption missing: App Store Connect will ask about encryption on every upload"

echo "== Privacy manifests"
for bundle in "$APP" "$APP/PlugIns/"*.appex; do
    name=$(basename "$bundle")
    if [ -f "$bundle/PrivacyInfo.xcprivacy" ]; then
        plutil -lint -s "$bundle/PrivacyInfo.xcprivacy" && pass "$name privacy manifest" || fail "$name privacy manifest invalid"
    else
        fail "$name has no PrivacyInfo.xcprivacy"
    fi
done
find "$APP/Frameworks" -name PrivacyInfo.xcprivacy 2>/dev/null | sed 's|.*/Frameworks/||;s|/PrivacyInfo.xcprivacy||' |
    while read -r fw; do pass "framework manifest: $fw"; done

echo "== Icon"
icon=App/Resources/Assets.xcassets/AppIcon.appiconset
big=$(ls "$icon"/*.png 2>/dev/null | while read -r f; do
    [ "$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')" = "1024" ] && echo "$f"; done | head -1)
if [ -n "$big" ]; then
    [ "$(sips -g hasAlpha "$big" | awk '/hasAlpha/{print $2}')" = "no" ] && pass "1024 icon without alpha" \
        || fail "1024 icon has an alpha channel"
else
    fail "no 1024 px app icon"
fi

echo "== No debug switches in Release"
if strings "$APP/KonstanzGo" | grep -q "KGPermissions\|KGFreshInstall\|KGDesignSystem"; then
    fail "debug launch switches compiled into Release"
else
    pass "debug switches only in Debug"
fi

echo "== Offline: no web addresses the app would call (but DWD's weather)"
hosts=$(strings "$APP/KonstanzGo" | grep -Eo "https?://[a-zA-Z0-9.-]+" | sort -u | grep -v "apple.com\|openstreetmap.org\|w3.org\|opendata.dwd.de" || true)
[ -z "$hosts" ] && pass "no unexpected hosts in the binary" || warn "hosts in the binary: $(echo $hosts)"

echo "== Translations (English for every German text)"
for target in KGFeatures KGDesign; do
    missing=$(python3 Design/tools/check_strings.py $target 2>&1 >/dev/null | grep -Eo "^[0-9]+")
    [ "$missing" = "0" ] && pass "$target English complete" || fail "$target: $missing texts without English"
done
if grep -q '"value" : "[^"]*!' Packages/KonstanzKit/Sources/*/Resources/*.xcstrings App/Resources/*.xcstrings \
    Widgets/Resources/*.xcstrings 2>/dev/null; then fail "texts with \"!\" left"; else pass "no \"!\" in texts"; fi

echo "== Lint"
errors=$(swiftlint lint --quiet 2>/dev/null | grep -c ": error:")
[ "$errors" = "0" ] && pass "SwiftLint: no errors" || fail "SwiftLint: $errors errors"

echo "== Size"
size=$(du -sh "$APP" | cut -f1)
pass "app bundle $size"

echo
[ $fails -eq 0 ] && echo "ALL CHECKS PASSED" || echo "$fails CHECK(S) FAILED"
exit $((fails > 0))
