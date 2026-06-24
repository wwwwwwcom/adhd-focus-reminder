#!/bin/bash
set -e
SDK=$(xcrun --sdk macosx --show-sdk-path)

echo "🔨 Building ADHD 专注提醒..."
clang -isysroot "$SDK" \
    -framework Cocoa \
    -framework WebKit \
    -framework CoreGraphics \
    -o "ADHD 专注提醒.app/Contents/MacOS/FocusBar" \
    FocusBar.m

echo "✍️  Signing..."
codesign --force --sign - "ADHD 专注提醒.app/Contents/MacOS/FocusBar"

echo "📋 Registering with Launch Services..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "ADHD 专注提醒.app" 2>/dev/null

echo "✅ Build complete."
echo ""
echo "To launch:  open 'ADHD 专注提醒.app'"
echo "To test:    click 🧠 in menu bar → ⚡ 测试弹窗"
