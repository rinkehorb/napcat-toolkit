#!/bin/bash
# ============================================================
#  按 config.env 渲染 systemd unit 并安装到 /etc/systemd/system/
#
#  用法: sudo bash install-systemd.sh
#  依赖: 同目录 config.env + 上级目录 systemd/ 里的 unit 模板
# ============================================================
set -e
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_SRC="$SELF_DIR/../systemd"

if [ ! -f "$SELF_DIR/config.env" ]; then
  echo "错误：缺少 $SELF_DIR/config.env（可从 config.env.example 复制）" >&2
  exit 1
fi
if [ "$(id -u)" != "0" ]; then
  echo "错误：请用 root 运行（需要写 /etc/systemd/system）" >&2
  exit 1
fi

# shellcheck disable=SC1091
. "$SELF_DIR/config.env"

NAPCAT_BASE="${NAPCAT_BASE:-/root/Napcat}"
NAPCAT_DIR="${NAPCAT_DIR:-$NAPCAT_BASE/opt/QQ/resources/app/app_launcher/napcat}"
QQ_EXE="${QQ_EXE:-$NAPCAT_BASE/opt/QQ/qq}"
TOOLS_DIR="${TOOLS_DIR:-$NAPCAT_BASE/tools}"
ASTRBOT_DIR="${ASTRBOT_DIR:-/root/astrbot}"
QQ_ACCOUNT="${QQ_ACCOUNT:-123456789}"

for f in napcat.service napcat-watchdog.service napcat-watchdog.timer astrbot.service; do
  [ -f "$UNIT_SRC/$f" ] || { echo "缺少模板 $UNIT_SRC/$f" >&2; exit 1; }
  sed -e "s|@NAPCAT_BASE@|${NAPCAT_BASE}|g" \
      -e "s|@NAPCAT_DIR@|${NAPCAT_DIR}|g" \
      -e "s|@QQ_EXE@|${QQ_EXE}|g" \
      -e "s|@QQ_ACCOUNT@|${QQ_ACCOUNT}|g" \
      -e "s|@TOOLS_DIR@|${TOOLS_DIR}|g" \
      -e "s|@ASTRBOT_DIR@|${ASTRBOT_DIR}|g" \
      "$UNIT_SRC/$f" > "/etc/systemd/system/$f"
  echo "已安装 /etc/systemd/system/$f"
done

systemctl daemon-reload
echo
echo "渲染结果检查（应无 @XXX@ 残留）："
grep -h '@[A-Z_]*@' /etc/systemd/system/napcat.service \
     /etc/systemd/system/napcat-watchdog.service \
     /etc/systemd/system/napcat-watchdog.timer \
     /etc/systemd/system/astrbot.service 2>/dev/null && echo "⚠️ 仍有未替换的占位符！" || echo "OK"
echo
echo "接着执行："
echo "  systemctl enable --now napcat astrbot"
echo "  systemctl enable --now napcat-watchdog.timer"
