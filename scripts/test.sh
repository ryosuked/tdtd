#!/bin/sh
# テストを種類ごとに選んで流す（CLAUDE.md §4）
#
#   scripts/test.sh scenario   シナリオ: 道具としての一連の流れ（Features の Tests/Scenario）。数秒で終わる
#   scripts/test.sh detail     細部: 値・表記・検証の場所まで（TodoCore・Persistence の Tests/Detail）。
#                              ファイルごとの行カバレッジも出し、90% 未満があれば失敗にする
#   scripts/test.sh all        両方（引数を省いたときも同じ）
set -eu
cd "$(dirname "$0")/.."

scenario() {
    echo "== scenario: Features"
    (cd Packages/Features && swift test)
}

# 細部のテストを流し、そのパッケージの Sources の行カバレッジ（%）を出す。
# 90% 未満のファイルが 1 つでもあれば失敗にする（CLAUDE.md §4）
detail() {
    for pkg in TodoCore Persistence; do
        echo "== detail: $pkg"
        (
            cd "Packages/$pkg"
            swift test --enable-code-coverage
            python3 - "$(swift test --show-codecov-path)" "$pkg" <<'EOF'
import json, sys
path, pkg = sys.argv[1], sys.argv[2]
files = [f for f in json.load(open(path))["data"][0]["files"] if f"/Sources/{pkg}/" in f["filename"]]
count = sum(f["summary"]["lines"]["count"] for f in files)
covered = sum(f["summary"]["lines"]["covered"] for f in files)
print(f"-- カバレッジ（行）: {pkg} {covered}/{count} = {covered / count * 100:.1f}%（目標 90%）")
low = []
for f in sorted(files, key=lambda f: f["summary"]["lines"]["percent"]):
    percent = f["summary"]["lines"]["percent"]
    mark = "  ✘" if percent < 90 else ""
    print(f"   {percent:5.1f}%  {f['filename'].split('/Sources/')[1]}{mark}")
    if percent < 90: low.append(f)
if low:
    sys.exit(f"-- 90% に届かないファイルが {len(low)} つある")
EOF
        )
    done
}

case "${1:-all}" in
    scenario) scenario ;;
    detail) detail ;;
    all) detail; scenario ;;
    *) echo "使い方: $0 [scenario|detail|all]" >&2; exit 2 ;;
esac
echo "OK"
