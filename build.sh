#!/usr/bin/env bash
# AutoGo iOS 巨魔版构建脚本
# 用法: ./build.sh [输出目录，默认 ./build]

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${1:-$PROJECT_ROOT/build}"
BUILD_DIR="$OUTPUT_DIR/xcode-build"
SCHEME="AutoGo"
APP_NAME="AutoGo"
BUNDLE_ID="com.autogo.ios"

echo "========================================"
echo "🚀 AutoGo iOS 巨魔版构建开始"
echo "📁 项目目录: $PROJECT_ROOT"
echo "📦 输出目录: $OUTPUT_DIR"
echo "========================================"

# 1. 检查环境
command -v xcodegen >/dev/null 2>&1 || {
    echo "❌ 未找到 xcodegen，正在安装..."
    brew install xcodegen
}

command -v xcodebuild >/dev/null 2>&1 || {
    echo "❌ 未找到 xcodebuild，请安装 Xcode Command Line Tools"
    exit 1
}

# 2. 生成 Xcode 项目
echo "📋 生成 Xcode 项目..."
cd "$PROJECT_ROOT"
xcodegen generate --spec project.yml

# 3. 清理并构建
echo "🔨 构建 Release 版本..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild \
    -project "$PROJECT_ROOT/AutoGo.xcodeproj" \
    -scheme "$SCHEME" \
    -sdk iphoneos \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/derived" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS="arm64" \
    VALID_ARCHS="arm64" \
    build

# 4. 定位 .app
APP_PATH=$(find "$BUILD_DIR/derived/Build/Products" -name "*.app" -type d | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo "❌ 未找到构建产物 .app"
    exit 1
fi

echo "✅ 找到 .app: $APP_PATH"

# 5. 使用 ldid 签名（巨魔版必需）
if command -v ldid >/dev/null 2>&1; then
    echo "🔏 使用 ldid 对 .app 进行签名..."
    ldid -S"$PROJECT_ROOT/AutoGo/AutoGo.entitlements" "$APP_PATH/$APP_NAME"
else
    echo "⚠️  未找到 ldid，尝试使用 codesign 临时签名..."
    codesign --force --sign - --entitlements "$PROJECT_ROOT/AutoGo/AutoGo.entitlements" "$APP_PATH" --deep
fi

# 6. 打包 .ipa
mkdir -p "$OUTPUT_DIR/Payload"
cp -R "$APP_PATH" "$OUTPUT_DIR/Payload/"

cd "$OUTPUT_DIR"
rm -f "$APP_NAME.ipa"
zip -qr "$APP_NAME.ipa" Payload
rm -rf Payload

echo ""
echo "========================================"
echo "🎉 构建成功!"
echo "📦 IPA 路径: $OUTPUT_DIR/$APP_NAME.ipa"
echo "========================================"
