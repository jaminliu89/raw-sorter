#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}"
app="${1:-$PWD/build/RAW 汇集.app}"
version="$(cat VERSION)"
zsh scripts/bootstrap.sh
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/exiftool/lib"
# Homebrew 的源文件可能只读；仅让本工具构建副本可更新，不修改安装源。
chmod -R u+w "$app/Contents/Resources/exiftool"
swiftc -swift-version 5 -O -target arm64-apple-macosx26.0 -framework AppKit -framework CryptoKit Engine.swift main.swift -o "$app/Contents/MacOS/RawSorter"
cp vendor/exiftool/exiftool "$app/Contents/Resources/exiftool/exiftool"
cp -R vendor/exiftool/lib/. "$app/Contents/Resources/exiftool/lib/"
cp vendor/exiftool/LICENSE "$app/Contents/Resources/exiftool/LICENSE"
cp vendor/exiftool/README "$app/Contents/Resources/exiftool/README"
cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
swiftc -swift-version 5 -framework AppKit scripts/BuildAssets.swift -o work/build-assets
work/build-assets "$PWD/work/assets"
iconutil -c icns work/assets/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
mkdir -p "$app/Contents/Resources/zh_CN.lproj"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RawSorter</string>
<key>CFBundleIdentifier</key><string>local.kim.raw-sorter</string>
<key>CFBundleName</key><string>RAW 汇集</string>
<key>CFBundleDisplayName</key><string>RAW 汇集</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>6</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>CFBundleLocalizations</key><array><string>zh_CN</string></array>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>26.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
printf '%s\n' "$app"
