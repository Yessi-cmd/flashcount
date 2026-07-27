#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$(mktemp -d /tmp/FlashCount-AltStore-DerivedData.XXXXXX)"
PACKAGE_ROOT="$(mktemp -d /tmp/FlashCount-AltStore-Package.XXXXXX)"
OUTPUT_DIR="$PROJECT_ROOT/build"
OUTPUT_IPA="$OUTPUT_DIR/FlashCount-AltStore.ipa"
TEMP_IPA="$OUTPUT_DIR/.FlashCount-AltStore.ipa.tmp.$$"

cleanup() {
    rm -rf "$DERIVED_DATA" "$PACKAGE_ROOT"
    rm -f "$TEMP_IPA"
}
trap cleanup EXIT

command -v xcodegen >/dev/null 2>&1 || {
    echo "error: xcodegen is required" >&2
    exit 1
}

mkdir -p "$OUTPUT_DIR"

(
    cd "$PROJECT_ROOT"
    ./scripts/generate-project.sh
)

xcodebuild \
    -project "$PROJECT_ROOT/FlashCount.xcodeproj" \
    -scheme FlashCount \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED_DATA" \
    clean build \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY='' \
    ENABLE_CODE_COVERAGE=NO \
    CLANG_COVERAGE_MAPPING=NO \
    GCC_GENERATE_TEST_COVERAGE_FILES=NO \
    GCC_INSTRUMENT_PROGRAM_FLOW_ARCS=NO

SOURCE_APP="$DERIVED_DATA/Build/Products/Release-iphoneos/FlashCount.app"
STAGED_APP="$PACKAGE_ROOT/Payload/FlashCount.app"

if [[ ! -x "$SOURCE_APP/FlashCount" ]]; then
    echo "error: unsigned app product was not created" >&2
    exit 1
fi

mkdir -p "$PACKAGE_ROOT/Payload"
ditto "$SOURCE_APP" "$STAGED_APP"

rm -rf "$STAGED_APP/PlugIns"
find "$STAGED_APP" -type d -name _CodeSignature -prune -exec rm -rf {} +
find "$STAGED_APP" -name embedded.mobileprovision -delete
xattr -cr "$STAGED_APP"
/usr/bin/xcrun strip -S -x "$STAGED_APP/FlashCount"

forbidden_content="$(find "$STAGED_APP" \( -name '*.appex' -o -name PlugIns -o -name _CodeSignature -o -name embedded.mobileprovision \) -print -quit)"
if [[ -n "$forbidden_content" ]]; then
    echo "error: forbidden AltStore package content remains: $forbidden_content" >&2
    exit 1
fi

if codesign --verify --deep --strict "$STAGED_APP" >/dev/null 2>&1; then
    echo "error: AltStore input app must be unsigned" >&2
    exit 1
fi

signature_details="$(codesign -dvvv "$STAGED_APP" 2>&1 || true)"
if [[ "$signature_details" != *"code object is not signed at all"* ]]; then
    echo "error: AltStore input app is not verifiably unsigned" >&2
    exit 1
fi

architectures="$(lipo -archs "$STAGED_APP/FlashCount")"
if [[ "$architectures" != "arm64" ]]; then
    echo "error: AltStore package must contain only arm64: $architectures" >&2
    exit 1
fi

if LC_ALL=C grep -a -F -q "$PROJECT_ROOT" "$STAGED_APP/FlashCount"; then
    echo "error: local project path is embedded in the Release executable" >&2
    exit 1
fi

if LC_ALL=C grep -R -a -E -q \
    'ProvisionedDevices|DeveloperCertificates|TeamIdentifier|com\.apple\.developer\.team-identifier' \
    "$STAGED_APP"; then
    echo "error: signing or provisioning identifiers remain in the AltStore package" >&2
    exit 1
fi

private_data="$(find "$STAGED_APP" -type f \( \
    -iname '*.sqlite' -o \
    -iname '*.sqlite3' -o \
    -iname '*.db' -o \
    -iname '*.csv' -o \
    -iname '*.bak' -o \
    -iname '*.backup' \
\) -print -quit)"
if [[ -n "$private_data" ]]; then
    echo "error: runtime or exported user data remains: $private_data" >&2
    exit 1
fi

rm -f "$TEMP_IPA"
(
    cd "$PACKAGE_ROOT"
    /usr/bin/zip -qry "$TEMP_IPA" Payload
)
unzip -tq "$TEMP_IPA" >/dev/null

mv -f "$TEMP_IPA" "$OUTPUT_IPA"
find "$OUTPUT_DIR" \
    -maxdepth 1 \
    -type f \
    -name '*.ipa' \
    ! -name 'FlashCount.ipa' \
    ! -name 'FlashCount-AltStore.ipa' \
    -delete

version="$(plutil -extract CFBundleShortVersionString raw "$STAGED_APP/Info.plist")"
build_number="$(plutil -extract CFBundleVersion raw "$STAGED_APP/Info.plist")"
checksum="$(shasum -a 256 "$OUTPUT_IPA" | awk '{print $1}')"

echo "Created: $OUTPUT_IPA"
echo "Version: $version ($build_number)"
echo "Architectures: $architectures"
echo "SHA-256: $checksum"
