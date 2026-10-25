#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h}
APP="$ROOT/build/首领助手.app"
SIGNING_IDENTITY=$(<"$ROOT/SigningIdentity.txt")
if ! security find-identity -v -p codesigning | /usr/bin/grep -Fq "$SIGNING_IDENTITY"; then
  print -u2 "固定签名证书不可用。请恢复本地签名证书，构建不会退回临时签名。"
  exit 1
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk -target arm64-apple-macosx14.0 -swift-version 5 -O -parse-as-library "$ROOT"/Sources/*.swift -o "$APP/Contents/MacOS/BossAssistant" -framework SwiftUI -framework AppKit -framework Network -framework CryptoKit
cp "$ROOT"/Resources/* "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.luca.HeroBossAssistant</string><key>CFBundleName</key><string>首领助手</string><key>CFBundleDisplayName</key><string>首领助手</string><key>CFBundleExecutable</key><string>BossAssistant</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>1.3.7</string><key>CFBundleVersion</key><string>21</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>NSHighResolutionCapable</key><true/><key>NSPrincipalClass</key><string>NSApplication</string><key>CFBundleIconFile</key><string>AppIcon</string></dict></plist>
PLIST
codesign --force --sign "$SIGNING_IDENTITY" --requirements "=designated => identifier \"local.luca.HeroBossAssistant\" and certificate leaf = H\"$SIGNING_IDENTITY\"" "$APP"
codesign --verify --deep --strict "$APP"
print "$APP"
