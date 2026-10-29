#!/bin/sh
# ほかの Mac へ持っていく用の Release ビルドを作り、zip にまとめる
#
# - Apple シリコンと Intel の両方で動く形（arm64 + x86_64）で作る
# - 署名はアドホックのまま。受け取った Mac では Gatekeeper に止められるので、
#   開き方は docs/dev_environment_setup.md §5 を見る
# - 出力: .build/release/Todo.app と .build/release/Todo.zip
set -eu
cd "$(dirname "$0")/.."

out=.build/release

echo "== xcodebuild: Todo (macOS, Release)"
xcodebuild -project Todo.xcodeproj -scheme Todo -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath .build/DerivedData -quiet build

rm -rf "$out"
mkdir -p "$out"
# ditto は拡張属性や署名を壊さずにコピー・圧縮する（cp や Finder の圧縮より安全）
ditto .build/DerivedData/Build/Products/Release/Todo.app "$out/Todo.app"

# Xcode はサンドボックスの権限と一緒に、デバッガをつなぐための権限（get-task-allow）も入れる。
# 配るビルドには要らないので、それだけを抜いて署名し直す（サンドボックスと Hardened Runtime は残す）
ent="$out/entitlements.plist"
codesign -d --entitlements - --xml "$out/Todo.app" > "$ent" 2>/dev/null
/usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' "$ent" 2>/dev/null || true
codesign --force --sign - --options runtime --entitlements "$ent" "$out/Todo.app" 2>/dev/null
rm "$ent"

ditto -c -k --keepParent "$out/Todo.app" "$out/Todo.zip"

echo "== 確認"
lipo -archs "$out/Todo.app/Contents/MacOS/Todo"
codesign --verify --deep --strict "$out/Todo.app" && echo "署名: OK（アドホック）"
echo "OK: $out/Todo.zip"
