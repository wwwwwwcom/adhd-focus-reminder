#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# ADHD 专注提醒 — 活动监测看门狗
# 仅在 10:00-19:00 期间监测用户活动
# 检测到「从空闲变为活跃」时自动启动应用
# 非工作时间完全休眠，不干预应用
# ═══════════════════════════════════════════════════════════════

WORK_START=10
WORK_END=19
POLL_INTERVAL=30
APP_NAME="ADHD 专注提醒"
APP_EXEC="/Users/wuhool/Downloads/ADHD/ADHD 专注提醒.app/Contents/MacOS/FocusBar"
LOG_DIR="$HOME/Library/Logs/ADHD"
LOG_FILE="$LOG_DIR/watchdog.log"

# 用户活跃阈值：最近 N 秒内有键盘/鼠标操作才认为活跃
ACTIVE_THRESHOLD=120  # 2 分钟

# 确保日志目录存在（~/Library/Logs 不会因重启清空）
mkdir -p "$LOG_DIR"

log() { echo "[$(date '+%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

is_running() { pgrep -x FocusBar > /dev/null 2>&1; }

# 读取 HID 空闲时间（纳秒），转换为秒
# macOS 用 IOHIDSystem 的 HIDIdleTime 记录最后一次键盘/鼠标/触摸板输入距今的时间
hid_idle_seconds() {
    local ns
    ns=$(ioreg -c IOHIDSystem -r -d 1 | grep HIDIdleTime | awk '{print $NF}')
    echo "${ns:-0}" | awk '{printf "%.0f", $1 / 1000000000}'
}

# 判断用户是否最近操作过键盘/鼠标
is_user_active() {
    local idle
    idle=$(hid_idle_seconds)
    (( idle < ACTIVE_THRESHOLD ))
}

# 检测屏幕是否处于锁屏状态（登录窗口/屏保密码界面）
# IOConsoleLocked = Yes 表示屏幕已锁定，此时即使有键盘/鼠标输入也不应启动应用
is_screen_locked() {
    ioreg -n Root -d1 | grep -q '"IOConsoleLocked" = Yes'
}

log "━━━ ADHD 看门狗启动 ━━━"
log "活跃阈值: ${ACTIVE_THRESHOLD}s（检测键盘/鼠标操作）"

# 记录上次启动时间，避免重复日志刷屏
last_launch_ts=0

while true; do
    HOUR=$(date +%H | sed 's/^0//')

    if (( HOUR >= WORK_START && HOUR < WORK_END )); then
        # ── 工作时间段：仅在用户活跃且未锁屏时才启动 FocusBar ──
        # 通过 HIDIdleTime 判断最近是否有键盘/鼠标操作，
        # 通过 IOConsoleLocked 判断屏幕是否锁定，
        # 避免用户不在电脑前或锁屏时自动弹出提醒窗口。
        if ! is_running; then
            if is_user_active && ! is_screen_locked; then
                now_ts=$(date +%s)
                # 5 分钟内不重复记录启动日志
                if (( now_ts - last_launch_ts > 300 )); then
                    log "🚀 检测到用户活跃，启动 $APP_NAME"
                    last_launch_ts=$now_ts
                fi
                nohup "$APP_EXEC" &>/dev/null &
                disown
            fi
        fi
    else
        # ── 非工作时间段：如果 FocusBar 在运行，杀掉它 ──
        if is_running; then
            log "🌙 非工作时间，关闭 $APP_NAME"
            pkill -x FocusBar 2>/dev/null || true
        fi
    fi

    sleep "$POLL_INTERVAL"
done
