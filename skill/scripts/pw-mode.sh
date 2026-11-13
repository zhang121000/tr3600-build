#!/bin/sh
# PassWall sing-box 运行时模式切换
#
# 前置条件：
#   - 主分流节点（_shunt）类型为 sing-box，变量 SHUNT 指向它
#   - 已存在 NORMAL / BOOST / BROAD 三个 _urltest 组
#   - 本机 socks 端口为 1070（PassWall 基本设置里的 node_socks_port）
#
# 用法：
#   pw-mode.sh normal   日常 1x/0.5x 组
#   pw-mode.sh boost    10x 高速组
#   pw-mode.sh broad    全部地区大池
#   pw-mode.sh status   查看当前模式 + Google 连通性

SHUNT="${SHUNT:-SB_SHUNT}"
NORMAL="${NORMAL:-UTFAST}"
BOOST="${BOOST:-UT10X}"
BROAD="${BROAD:-UTDAILY}"
SOCKS_PORT="${SOCKS_PORT:-1070}"
LOG="${LOG:-/root/pw-mode.log}"

case "$1" in
  normal) node="$NORMAL" ;;
  boost)  node="$BOOST" ;;
  broad)  node="$BROAD" ;;
  status)
    echo "current default: $(uci get passwall.$SHUNT.default_node 2>/dev/null)"
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 \
      --socks5-hostname "127.0.0.1:$SOCKS_PORT" \
      https://www.google.com/generate_204 2>/dev/null)
    echo "google test: $code"
    exit 0 ;;
  *)
    echo "usage: $0 normal|boost|broad|status"
    exit 1 ;;
esac

prev=$(uci get passwall.$SHUNT.default_node 2>/dev/null)
[ -z "$prev" ] && prev="$NORMAL"

uci set passwall.$SHUNT.default_node="$node"
uci commit passwall
/etc/init.d/passwall restart
sleep 5

code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
  --socks5-hostname "127.0.0.1:$SOCKS_PORT" \
  https://www.google.com/generate_204 2>/dev/null)

if [ "$code" != "204" ]; then
  echo "$(date '+%F %T') switch $1 -> $node FAILED code=$code, revert to $prev" >> "$LOG"
  uci set passwall.$SHUNT.default_node="$prev"
  uci commit passwall
  /etc/init.d/passwall restart
  echo "switch failed, reverted to $prev"
  exit 2
fi

echo "$(date '+%F %T') mode=$1 default=$node ok" >> "$LOG"
echo "mode=$1 default=$node"
