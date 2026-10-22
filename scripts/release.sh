#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(cat VERSION)"
app="$PWD/build/RAW 汇集.app"
mkdir -p work dist
bash scripts/bootstrap.sh
bash scripts/test.sh
zsh build.sh "$app"
codesign --verify --deep --strict "$app"
# 真正以空 PATH 环境运行包内入口，防止仅在开发机上依赖 Homebrew。
env -i PATH=/usr/bin:/bin HOME="$HOME" "$app/Contents/MacOS/RawSorter" --inspect "$PWD/work/fixtures" > work/isolated-smoke.log 2>&1
cat work/isolated-smoke.log
if /usr/bin/grep -En '/opt/homebrew|/usr/local|Cellar' work/isolated-smoke.log; then
  echo '隔离冒烟检测到外部运行依赖'; exit 1
fi
otool -L "$app/Contents/MacOS/RawSorter" > work/runtime-libraries.txt
if /usr/bin/grep -E '/opt/homebrew|/usr/local|Cellar' work/runtime-libraries.txt; then exit 1; fi
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/RAW-Sorter-$version-macOS-arm64.zip"
"${DMGBUILD:-dmgbuild}" -s scripts/dmg-settings.py -D app="$app" -D background="$PWD/work/assets/dmg-background.png" -D manual="$PWD/work/assets/使用说明.pdf" "RAW Sorter $version" "dist/RAW-Sorter-$version-macOS-arm64.dmg"
hdiutil verify "dist/RAW-Sorter-$version-macOS-arm64.dmg"
cd dist
shasum -a 256 "RAW-Sorter-$version-macOS-arm64.dmg" "RAW-Sorter-$version-macOS-arm64.zip" > SHA256SUMS.txt
