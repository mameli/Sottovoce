#!/bin/sh
# Builds the Debug app and links build/sottovoce to its executable, the way Homebrew will link
# the installed one: run ./build/sottovoce <video>.
set -e
cd "$(dirname "$0")/.."
xcodebuild -project Sottovoce.xcodeproj -scheme Sottovoce -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData -quiet build
ln -sf "$PWD/build/DerivedData/Build/Products/Debug/Sottovoce.app/Contents/MacOS/Sottovoce" build/sottovoce
echo "build/sottovoce -> Debug Sottovoce.app"
