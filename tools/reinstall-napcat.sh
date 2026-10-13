#!/bin/bash
# ============================================================
#  从零重装 NapCat（Shell / rootless 方式）
#
#  特点：全程走国内 GitHub 加速镜像，不需要 GitHub 直连、不需要代理。
#        优先使用本地离线包 /root/napcat-offline/NapCat.Shell.zip。
#
#  ⚠️ 注意：官方安装脚本把安装目录写死为 $HOME/Napcat，
#           所以 config.env 里的 NAPCAT_BASE 必须是 $HOME/Napcat。
#
#  用法: sudo bash reinstall-napcat.sh
#  依赖: 同目录 config.env
# ============================================================
set -e
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$SELF_DIR/config.env" ]; then
  echo "错误：缺少 $SELF_DIR/config.env（可从 config.env.example 复制）" >&2
  exit 1
fi
# shellcheck disable=SC1091
. "$SELF_DIR/config.env"

GH="${GITHUB_MIRROR:-https://ghfast.top}"
ZIP_DIR="${ZIP_DIR:-/root/napcat-offline}"
NAPCAT_BASE="${NAPCAT_BASE:-$HOME/Napcat}"

mkdir -p "$ZIP_DIR"
cd /root

echo "[1/5] 下载官方安装脚本（经 ${GH} 镜像）"
curl -fL -o /root/napcat.sh \
  "$GH/https://raw.githubusercontent.com/NapNeko/NapCat-Installer/main/script/install.sh"

echo "[2/5] 准备 NapCat.Shell.zip（有离线包就直接用）"
if [ ! -s "$ZIP_DIR/NapCat.Shell.zip" ]; then
  curl -fL --retry 3 -o "$ZIP_DIR/NapCat.Shell.zip" \
    "$GH/https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip"
fi
unzip -t "$ZIP_DIR/NapCat.Shell.zip" >/dev/null 2>&1 || { echo "压缩包损坏，请删除后重试"; exit 1; }
cp -f "$ZIP_DIR/NapCat.Shell.zip" /root/NapCat.Shell.zip

echo "[3/5] 准备 QQ 本体（缺则从 /opt/QQ 复制，省 ~150MB 下载）"
if [ ! -f "$NAPCAT_BASE/opt/QQ/resources/app/package.json" ]; then
  mkdir -p "$NAPCAT_BASE/opt"
  cp -a /opt/QQ "$NAPCAT_BASE/opt/QQ"
  echo "     已复制 /opt/QQ → $NAPCAT_BASE/opt/QQ"
else
  echo "     已存在，跳过"
fi

echo "[4/5] 注入 NapCat（--docker n 走 Shell 方式；--proxy 0 表示用本地包不测网速）"
bash /root/napcat.sh --docker n --cli n --proxy 0

echo "[5/5] 完成。接着执行："
echo "      systemctl restart napcat"
echo "      bash $SELF_DIR/check-health.sh"
