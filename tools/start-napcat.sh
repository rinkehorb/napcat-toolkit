#!/bin/bash
# ============================================================
#  手动兜底启动 NapCat（仅在 systemd 不可用时使用）
#
#  ⚠️ 注意：工作目录必须是 NapCat 运行目录，
#           因为 NapCat 的 config/ 和 cache/ 都在其下。
#
#  用法: nohup ./start-napcat.sh > /var/log/napcat-manual.log 2>&1 &
#  依赖: 同目录 config.env
# ============================================================
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[ -f "$SELF_DIR/config.env" ] && . "$SELF_DIR/config.env"

NAPCAT_DIR="${NAPCAT_DIR:-/root/Napcat/opt/QQ/resources/app/app_launcher/napcat}"
QQ_EXE="${QQ_EXE:-/root/Napcat/opt/QQ/qq}"
QQ_ACCOUNT="${QQ_ACCOUNT:-123456789}"

cd "$NAPCAT_DIR" || { echo "找不到 NapCat 运行目录: $NAPCAT_DIR" >&2; exit 1; }
echo "启动 NapCat：账号 $QQ_ACCOUNT，工作目录 $NAPCAT_DIR"
exec xvfb-run -a "$QQ_EXE" --no-sandbox -q "$QQ_ACCOUNT"
