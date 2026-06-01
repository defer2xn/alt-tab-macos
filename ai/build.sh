#!/bin/bash
set -e

xcodebuild \
  -project alt-tab-macos.xcodeproj \
  -scheme Release \
  -configuration Release \
  -derivedDataPath DerivedData

# 编译通过后才安装：自签名 + 版本号由 config/local.xcconfig 自动注入
rm -rf /Applications/AltTab.app
cp -R DerivedData/Build/Products/Release/AltTab.app /Applications/
