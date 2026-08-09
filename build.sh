#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
DERIVED_DATA="${BUILD_DIR}/DerivedData"
OUTPUT_DIR="${BUILD_DIR}/output"
SCHEME="AutoLua"
CONFIGURATION="Release"

echo "=== AutoLua iOS Build ==="

# Clean
rm -rf "${BUILD_DIR}"
mkdir -p "${OUTPUT_DIR}"

# Generate Xcode project with xcodegen
echo "[1/4] Generating Xcode project..."
if command -v xcodegen &> /dev/null; then
    cd "${PROJECT_DIR}"
    xcodegen generate
else
    echo "ERROR: xcodegen not found. Install: brew install xcodegen"
    exit 1
fi

# Build
echo "[2/4] Building..."
xcodebuild \
    -project "${PROJECT_DIR}/AutoLua.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -derivedDataPath "${DERIVED_DATA}" \
    -destination 'generic/platform=iOS' \
    -archivePath "${BUILD_DIR}/AutoLua.xcarchive" \
    archive \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    ONLY_ACTIVE_ARCH=NO

# Export IPA
echo "[3/4] Creating IPA..."
APP_PATH="${BUILD_DIR}/AutoLua.xcarchive/Products/Applications/AutoLua.app"

mkdir -p "${OUTPUT_DIR}/Payload"
cp -R "${APP_PATH}" "${OUTPUT_DIR}/Payload/"

cd "${OUTPUT_DIR}"
zip -qr "AutoLua.ipa" "Payload"
rm -rf "Payload"

echo "[4/4] Signing with ldid..."
if command -v ldid &> /dev/null; then
    ldid -S"${PROJECT_DIR}/AutoLua/Entitlements.entitlements" "${APP_PATH}/AutoLua"
    echo "Signed successfully"
else
    echo "WARNING: ldid not found. IPA not fakesigned."
    echo "Install: brew install ldid"
fi

echo ""
echo "=== Build Complete ==="
echo "IPA: ${OUTPUT_DIR}/AutoLua.ipa"
