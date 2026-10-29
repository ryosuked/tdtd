#!/bin/sh
# 全パッケージのテストと、macOS 向けのアプリのビルドを流す
set -eu
cd "$(dirname "$0")/.."

for pkg in TodoCore Persistence; do
    echo "== swift test: $pkg"
    (cd "Packages/$pkg" && swift test)
done

echo "== swift build: Features"
(cd Packages/Features && swift build)

echo "== xcodebuild: Todo (macOS)"
xcodebuild -project Todo.xcodeproj -scheme Todo -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath .build/DerivedData -quiet build
echo "OK"
