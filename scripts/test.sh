#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work/fixtures
python3 scripts/make-fixtures.py "$PWD/work/fixtures"
export RAW_TEST_SOURCE_A="${RAW_TEST_SOURCE_A:-$PWD/work/fixtures/A.ARW}"
export RAW_TEST_SOURCE_B="${RAW_TEST_SOURCE_B:-$PWD/work/fixtures/B.ARW}"
export RAW_EXIFTOOL="${RAW_EXIFTOOL:-$PWD/vendor/exiftool/exiftool}"
swiftc -swift-version 5 -O -framework CryptoKit Engine.swift Tests.swift -o work/test-engine
work/test-engine "$PWD/work" "$@"
