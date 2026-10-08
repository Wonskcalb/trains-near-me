#!/bin/sh
# Renders the README / guide / social images in Design/ from the real widget views.
set -eu
cd "$(dirname "$0")/.."

if ! xcodebuild -version >/dev/null 2>&1 && [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

copy=Design/Screenshots/Sources/Screenshots/Widget
rm -rf "$copy" && mkdir -p "$copy"
cp Widget/*.swift "$copy/"

# Outside WidgetKit the family is read-only and containerBackground draws nothing,
# so the copy takes the family as a parameter and paints its background itself.
view="$copy/DeparturesWidget.swift"
sed -i '' \
    -e 's/^@main$//' \
    -e 's/@Environment(\\.widgetFamily) private var family/var family: WidgetFamily = .systemMedium/' \
    -e 's/\.containerBackground(for: \.widget) {/.padding(16).background {/' \
    "$view"
for expected in 'var family: WidgetFamily' '.padding(16).background {'; do
    grep -qF "$expected" "$view" || { echo "DeparturesWidget.swift changed: update the substitutions in $0" >&2; exit 1; }
done

swift run --package-path Design/Screenshots -c release Screenshots "$PWD/Design"
ls -1 Design/*.png
