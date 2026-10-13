#!/bin/bash
# ============================================================
#  NapCat 健康看门狗 v2
#
#  背景：NapCat(Shell) 启动时约 50% 概率会「假死」——
#        日志停在 [WebUi] WebUi Token 那一行，永远不走登录流程；
#        进程不崩、systemd 显示 active、WebUI 端口甚至能打开，
#        但反向 WS 永远不建立，机器人实际不工作。
#        此时重启 napcat 能救活（成功率约 50%），所以策略是：
#        「发现假死就快速重试，直到连上为止」。
#
#  保护：
#    * 启动宽限期内不判定
#    * 正在等扫码时绝不动手（否则二维码被刷掉，永远登不上）
#    * 限速 + 次数上限，避免无限重启把机器拖垮
#
#  用法：由 napcat-watchdog.timer 每 30 秒调用一次，也可手动执行。
#  依赖：同目录 config.env（可从 config.env.example 复制）
# ============================================================
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[ -f "$SELF_DIR/config.env" ] && . "$SELF_DIR/config.env"

LOG="${WATCHDOG_LOG:-/var/log/napcat-watchdog.log}"
NAPCAT_CACHE_DIR="${NAPCAT_CACHE_DIR:-/root/Napcat/opt/QQ/resources/app/app_launcher/napcat/cache}"
GRACE="${WD_GRACE:-90}"
FAST_GAP="${WD_FAST_GAP:-90}"
FAST_TIMES="${WD_FAST_TIMES:-5}"
SLOW_GAP="${WD_SLOW_GAP:-300}"
MAX_ATTEMPTS="${WD_MAX_ATTEMPTS:-12}"

STATE=/run/napcat-watchdog
mkdir -p "$STATE"
FAILS="$STATE/fails"; LAST="$STATE/last_restart"; ATT="$STATE/attempts"

ts(){ date '+%F %T'; }
log(){ echo "$(ts) $*" >> "$LOG"; }
num(){ case "${1:-}" in ''|*[!0-9]*) echo "${2:-0}";; *) echo "$1";; esac; }

# 1) 服务不是 active → 交给 systemd 的 Restart=always，不插手
[ "$(systemctl is-active napcat 2>/dev/null)" = "active" ] || { echo 0 > "$FAILS"; exit 0; }

# 2) 已运行时长（秒）
enter=$(systemctl show -p ActiveEnterTimestampMonotonic --value napcat 2>/dev/null)
case "$enter" in ''|*[!0-9]*) exit 0;; esac
now_us=$(awk '{printf "%d", $1*1000000}' /proc/uptime)
elapsed=$(( (now_us - enter) / 1000000 ))
[ "$elapsed" -lt "$GRACE" ] && exit 0          # 启动宽限期

# 3) 连接正常 → 计数清零
if ss -tna 2>/dev/null | grep ESTAB | grep -q '127\.0\.0\.1:6199'; then
  echo 0 > "$FAILS"; echo 0 > "$ATT"; exit 0
fi

# 4) 正在等扫码 → 千万别动，否则二维码被刷掉永远登不上
if journalctl -u napcat --since "$(date -d '-5 min' '+%F %T')" --no-pager 2>/dev/null | grep -qE '二维码|扫码'; then
  log "等扫码中，跳过（不打断登录）"; exit 0
fi
if find "$NAPCAT_CACHE_DIR" -name 'qrcode*' -newermt '-10 minutes' 2>/dev/null | grep -q .; then
  log "发现新二维码文件，跳过"; exit 0
fi

# 5) 连续两次命中才动手（避免误判瞬时抖动）
f=$(( $(num "$(cat "$FAILS" 2>/dev/null)") + 1 )); echo "$f" > "$FAILS"
if [ "$f" -lt 2 ]; then
  log "第 $f 次检测到无连接（已运行 ${elapsed}s），再观察一轮"; exit 0
fi

# 6) 重试节奏：前 FAST_TIMES 次用 FAST_GAP 快速收敛，之后退避到 SLOW_GAP
last=$(num "$(cat "$LAST" 2>/dev/null)"); att=$(num "$(cat "$ATT" 2>/dev/null)")
now=$(date +%s)
if [ "$att" -lt "$FAST_TIMES" ]; then gap="$FAST_GAP"; else gap="$SLOW_GAP"; fi
if [ $((now - last)) -lt "$gap" ]; then
  log "未到重试间隔（$((now - last))s < ${gap}s，已尝试 ${att} 次），跳过"; exit 0
fi
if [ "$att" -ge "$MAX_ATTEMPTS" ]; then
  log "已自动重启 ${att} 次仍未连上，本轮跳过（请人工检查：journalctl -u napcat -n 80）"; exit 0
fi

log "确认假死：active 已 ${elapsed}s 但 6199 无 ESTAB → 第 $((att+1)) 次重启 napcat"
echo "$now" > "$LAST"; echo $((att+1)) > "$ATT"; echo 0 > "$FAILS"
systemctl restart napcat
