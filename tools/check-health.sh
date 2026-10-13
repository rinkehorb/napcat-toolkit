#!/bin/bash
# ============================================================
#  NapCat + AstrBot 一键体检
#  用法: bash check-health.sh
#  依赖: 同目录 config.env（可从 config.env.example 复制）
# ============================================================
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[ -f "$SELF_DIR/config.env" ] && . "$SELF_DIR/config.env"

# 默认值（没有 config.env 也能跑）
NAPCAT_CONFIG_DIR="${NAPCAT_CONFIG_DIR:-/root/Napcat/opt/QQ/resources/app/app_launcher/napcat/config}"
WATCHDOG_LOG="${WATCHDOG_LOG:-/var/log/napcat-watchdog.log}"
PORT_ASTRBOT_WEBUI="${PORT_ASTRBOT_WEBUI:-6185}"
PORT_ONEBOT_WS="${PORT_ONEBOT_WS:-6199}"
PORT_NAPCAT_WEBUI="${PORT_NAPCAT_WEBUI:-6099}"
WD_GRACE="${WD_GRACE:-90}"
WEBUI_HOST="${WEBUI_HOST:-$(hostname -I 2>/dev/null | awk '{print $1}')}"

clean() { sed 's/\x1b\[[0-9;]*m//g'; }

echo "--- 服务状态 ---"
for s in astrbot napcat; do
  printf "%-8s %s / 开机自启:%s\n" "$s" "$(systemctl is-active "$s" 2>/dev/null)" "$(systemctl is-enabled "$s" 2>/dev/null)"
done
printf "%-8s %s\n" "看门狗" "$(systemctl is-active napcat-watchdog.timer 2>/dev/null) / 开机自启:$(systemctl is-enabled napcat-watchdog.timer 2>/dev/null)"

echo "--- 端口 ---"
ss -tlnp 2>/dev/null | grep -E ":${PORT_ASTRBOT_WEBUI}|:${PORT_ONEBOT_WS}|:${PORT_NAPCAT_WEBUI}" || echo "无端口监听"

echo "--- NapCat <-> AstrBot 反向WS ---"
if ss -tna 2>/dev/null | grep ESTAB | grep -q "127.0.0.1:${PORT_ONEBOT_WS}"; then
  echo "正常：已连接"
else
  echo "异常：${PORT_ONEBOT_WS} 无 ESTAB（看门狗会在 ${WD_GRACE} 秒内自动重启 NapCat 自愈）"
fi

echo "--- 登录状态（本次开机）---"
journalctl -u napcat -b --no-pager 2>/dev/null | clean \
  | grep -oE '正在快速登录 *[0-9]+|登录成功|二维码' | tail -3

echo "--- 本次开机 NapCat 启动了几次（俗称抽卡）---"
printf "napcat 启动次数: %s   看门狗出手次数: %s\n" \
  "$(journalctl -u napcat -b --no-pager 2>/dev/null | grep -c 'Started napcat.service')" \
  "$(wc -l < "$WATCHDOG_LOG" 2>/dev/null || echo 0)"

echo "--- NapCat WebUI ---"
jq -r --arg h "$WEBUI_HOST" --arg p "$PORT_NAPCAT_WEBUI" \
  '"http://" + $h + ":" + $p + "/webui?token=" + .token' \
  "$NAPCAT_CONFIG_DIR/webui.json" 2>/dev/null || echo "(读不到 webui.json)"

echo "--- 近期真实异常（dbus/Bugly 属无桌面环境的正常噪音，已过滤）---"
journalctl -u napcat -n 200 --no-pager 2>/dev/null | clean | grep -Ei 'error|失败' \
  | grep -viE 'dbus|Bugly|NativeCrashHandler|rqd_record' | tail -4

echo "--- 看门狗日志（自愈记录）---"
tail -5 "$WATCHDOG_LOG" 2>/dev/null || echo "(空 = 没触发过自愈)"
