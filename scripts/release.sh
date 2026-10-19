#!/bin/sh
# Archives Trains near me for one platform and either uploads it to App Store Connect (TestFlight)
# or only exports it, which is the dry run: same archive and signing, nothing sent.
#
#   sh scripts/release.sh ios|macos [upload|export]
#
# Signing comes from DEVELOPMENT_TEAM / BUNDLE_ID_PREFIX (Config/Local.xcconfig locally, the
# environment on CI). On CI an App Store Connect API key lets Xcode fetch the App Store provisioning
# profiles itself: set ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID. The certificates must already be in
# the keychain (the release workflow imports them).
#
# MARKETING_VERSION overrides project.yml's (the release workflow passes the tag's). The build number
# stays project.yml's CURRENT_PROJECT_VERSION, bumped by hand before tagging.
#
# The SNCF token is never compiled into a distributed build: SNCF_TOKEN is forced empty, and testers
# type their own in Settings (a paid team has the App Group that carries it to the widget).
set -eu
cd "$(dirname "$0")/.."

platform=${1:?usage: release.sh ios|macos [upload|export]}
mode=${2:-export}
case "$platform" in
    ios) destination="generic/platform=iOS" ;;
    macos) destination="generic/platform=macOS" ;;
    *) echo "platform must be ios or macos" >&2; exit 2 ;;
esac
case "$mode" in upload|export) ;; *) echo "mode must be upload or export" >&2; exit 2 ;; esac

out="build/release/$platform"
rm -rf "$out" && mkdir -p "$out"

overrides="SNCF_TOKEN="
[ -n "${DEVELOPMENT_TEAM:-}" ] && overrides="$overrides DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM"
[ -n "${BUNDLE_ID_PREFIX:-}" ] && overrides="$overrides BUNDLE_ID_PREFIX=$BUNDLE_ID_PREFIX"
[ -n "${MARKETING_VERSION:-}" ] && overrides="$overrides MARKETING_VERSION=$MARKETING_VERSION"

# With an API key Xcode can create and download the App Store provisioning profiles on a machine that
# has never seen them (a fresh CI runner); without one it uses the Xcode account signed in locally.
auth="-allowProvisioningUpdates"
if [ -n "${ASC_KEY_PATH:-}" ]; then
    auth="$auth -authenticationKeyPath $ASC_KEY_PATH -authenticationKeyID $ASC_KEY_ID -authenticationKeyIssuerID $ASC_ISSUER_ID"
fi

# shellcheck disable=SC2086 # the override and auth lists are meant to split into arguments
xcodebuild archive -project TrainsNearMe.xcodeproj -scheme TrainsNearMe -configuration Release \
    -destination "$destination" -archivePath "$out/TrainsNearMe.xcarchive" -derivedDataPath build/release/derived \
    $auth $overrides

cat > "$out/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>$mode</string>
    <key>signingStyle</key><string>automatic</string>
    <key>manageAppVersionAndBuildNumber</key><false/>
    <key>uploadSymbols</key><true/>
</dict>
</plist>
EOF

# shellcheck disable=SC2086
xcodebuild -exportArchive -archivePath "$out/TrainsNearMe.xcarchive" -exportOptionsPlist "$out/ExportOptions.plist" \
    -exportPath "$out/export" $auth

if [ "$mode" = upload ]; then
    echo "Uploaded $platform to App Store Connect: it shows in TestFlight once processing ends."
else
    echo "Exported $platform to $out/export (not uploaded)."
fi
