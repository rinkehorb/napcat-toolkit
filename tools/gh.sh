#!/bin/bash
# ============================================================
#  让「单条命令」经本地 SOCKS5 代理访问 GitHub 官方源
#
#  用法: ./gh.sh git clone https://github.com/xxx/yyy
#        ./gh.sh curl -s https://api.github.com/repos/NapNeko/NapCatQQ/releases/latest
#
#  说明: 只给这一条命令注入代理环境变量，不改全局代理，
#        不影响 QQ / AstrBot 等其它流量的直连。
#  依赖: 同目录 config.env 里的 PROXY_SOCKS
#        （例：局域网里跑 Clash/FlClash 的那台机器，socks5h://<IP>:7890）
# ============================================================
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[ -f "$SELF_DIR/config.env" ] && . "$SELF_DIR/config.env"

PROXY_SOCKS="${PROXY_SOCKS:-}"
NO_PROXY_LIST="${NO_PROXY_LIST:-localhost,127.0.0.1,::1}"

if [ -z "$PROXY_SOCKS" ]; then
  echo "错误：未配置代理。请在本目录 config.env 里设置 PROXY_SOCKS，例如" >&2
  echo '  PROXY_SOCKS="socks5h://192.168.1.2:7890"' >&2
  echo "（如果不需要代理，直接用镜像源即可，例如：https://ghfast.top/https://github.com/...）" >&2
  exit 1
fi

export ALL_PROXY="$PROXY_SOCKS"
export HTTPS_PROXY="$PROXY_SOCKS" HTTP_PROXY="$PROXY_SOCKS"
export NO_PROXY="$NO_PROXY_LIST"
exec "$@"
