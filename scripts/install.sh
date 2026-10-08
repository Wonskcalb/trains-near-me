#!/bin/sh
# Builds Trains near me with your free Apple account and installs it in /Applications.
set -eu
cd "$(dirname "$0")/.."

if ! xcodebuild -version >/dev/null 2>&1; then
    if [ -d /Applications/Xcode.app ]; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    else
        echo "Xcode is required: install it from the Mac App Store, open it once, then run this script again." >&2
        exit 1
    fi
fi

if [ ! -f Config/Local.xcconfig ]; then
    # The team id is the OU field of the "Apple Development" certificate Xcode creates for your Apple ID.
    # ponytail: takes the first certificate found; edit Config/Local.xcconfig if you belong to several teams.
    team=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
        | openssl x509 -noout -subject 2>/dev/null \
        | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p')
    if [ -z "$team" ]; then
        echo "No Apple Development certificate found." >&2
        echo "In Xcode: Settings › Accounts › add your Apple ID › Manage Certificates… › + › Apple Development." >&2
        exit 1
    fi
    user=$(id -un | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
    printf 'DEVELOPMENT_TEAM = %s\nBUNDLE_ID_PREFIX = io.github.%s.trainsnearme\n' "$team" "$user" > Config/Local.xcconfig
    echo "Created Config/Local.xcconfig for team $team."
fi

echo "Building… (a minute or two the first time)"
xcodebuild -project TrainsNearMe.xcodeproj -scheme TrainsNearMe -configuration Release -destination "generic/platform=macOS" \
    -derivedDataPath build -allowProvisioningUpdates -quiet build

built="build/Build/Products/Release/Trains near me.app"
dest="${INSTALL_DIR:-/Applications}/Trains near me.app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

osascript -e 'quit app "Trains near me"' >/dev/null 2>&1 || true
rm -rf "$dest"
ditto "$built" "$dest"
# Two registered copies of the same widget make macOS pick one at random.
"$lsregister" -u "$built" >/dev/null 2>&1 || true
"$lsregister" -f "$dest"
open "$dest"
echo "Installed: $dest"
