#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=13.55
expected=5c9d422ad128fab728aacc5cc0aa77095d14cde74931389dd961d3d720e6b316
mkdir -p vendor work
if [[ -f vendor/exiftool/exiftool ]]; then
  [[ "$(/usr/bin/perl vendor/exiftool/exiftool -ver)" == "$version" ]] || { echo 'ExifTool 版本不匹配'; exit 1; }
  exit 0
fi
archive="work/exiftool-$version.tar.gz"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 --max-time 180 "https://codeload.github.com/exiftool/exiftool/tar.gz/refs/tags/$version" -o "$archive"
fi
actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
[[ "$actual" == "$expected" ]] || { echo 'ExifTool 下载校验失败'; exit 1; }
stage="$(mktemp -d "$PWD/work/exiftool.XXXXXX")"
tar -xzf "$archive" -C "$stage"
mv "$stage/exiftool-$version" vendor/exiftool
/usr/bin/perl vendor/exiftool/exiftool -ver
