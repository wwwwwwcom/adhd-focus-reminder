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

# ═══════════════════════════════════════════════════════════════
# 安装活动监测看门狗
# ═══════════════════════════════════════════════════════════════
WATCHDOG_DIR="$HOME/Library/Application Support/ADHD"
WATCHDOG_SCRIPT="$WATCHDOG_DIR/watchdog.sh"
PLIST_SRC="com.adhd.focus-watchdog.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.adhd.focus-watchdog.plist"

echo "🔧 安装看门狗..."

# 创建稳定目录
mkdir -p "$WATCHDOG_DIR"

# 复制看门狗脚本到固定位置
cp watchdog.sh "$WATCHDOG_SCRIPT"
chmod +x "$WATCHDOG_SCRIPT"

# 更新 plist 中的脚本路径（确保指向正确）
sed -i '' "s|/Users/wuhool/Library/Application Support/ADHD/watchdog.sh|$WATCHDOG_SCRIPT|g" "$PLIST_SRC"

# 安装 LaunchAgent
mkdir -p "$HOME/Library/LaunchAgents"
cp "$PLIST_SRC" "$PLIST_DST"

# 卸载旧版本（如果存在）然后重新加载
launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load "$PLIST_DST"

echo "✅ 看门狗已安装并启动"
echo ""
echo "To launch:  open 'ADHD 专注提醒.app'"
echo "To test:    click 🧠 in menu bar → ⚡ 测试弹窗"
echo ""
echo "📋 看门狗状态:"
echo "   监测时段: 10:00 - 19:00"
echo "   日志:     /tmp/adhd-watchdog.log"
echo "   状态:     launchctl list | grep focus-watchdog"
