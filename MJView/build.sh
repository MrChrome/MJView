#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$SCRIPT_DIR/../MJView.xcodeproj"
SCHEME="MJView"
CONFIGURATION="${1:-Debug}"
STAGING="/tmp/MJView-build"
OUTPUT="$SCRIPT_DIR/MJView.app"

echo "Building $SCHEME ($CONFIGURATION) → $OUTPUT"

run_build() {
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    CONFIGURATION_BUILD_DIR="$STAGING" \
    OBJROOT="$STAGING/obj" \
    build
}

run_build | xcpretty || run_build

rm -rf "$OUTPUT"
cp -R "$STAGING/MJView.app" "$OUTPUT"
