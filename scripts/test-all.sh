#!/bin/sh
# 全部のテスト（細部とシナリオ。scripts/test.sh all）と、macOS 向けのアプリのビルドを流す
set -eu
cd "$(dirname "$0")/.."

./scripts/test.sh all

echo "== xcodebuild: Todo (macOS)"
xcodebuild -project Todo.xcodeproj -scheme Todo -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath .build/DerivedData -quiet build
echo "OK"
