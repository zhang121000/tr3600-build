#!/bin/bash
# Cudy TR3600 刷机脚本：通过 LuCI 后台上传固件并刷入
# 用法：./flash.sh <固件路径> [路由器IP] [密码]
# 密码建议通过第 3 个参数或 ROUTER_PASS 环境变量传入，不要写死在脚本里

set -e
FW="${1:?用法: $0 <固件路径> [路由器IP] [密码]}"
ROUTER="${2:-192.168.2.1}"
PASS="${3:-${ROUTER_PASS}}"
[ -z "$PASS" ] && { echo "请通过第 3 个参数或 ROUTER_PASS 环境变量提供路由器密码"; exit 1; }
COOKIE=/tmp/luci_flash_cookie.txt
rm -f "$COOKIE"

echo "==> 登录 LuCI"
curl -s -c "$COOKIE" -b "$COOKIE" -X POST "http://$ROUTER/cgi-bin/luci/" \
  --data "luci_username=root&luci_password=$PASS" -o /dev/null

SID=$(grep sysauth "$COOKIE" | awk '{print $NF}')
[ -z "$SID" ] && { echo "登录失败，检查密码"; exit 1; }

echo "==> 上传固件（$(basename "$FW")）"
curl -s -b "$COOKIE" -X POST "http://$ROUTER/cgi-bin/cgi-upload" \
  -F "sessionid=$SID" -F "filename=/tmp/firmware.bin" \
  -F "filedata=@$FW" --max-time 300 | python3 -c \
  "import json,sys; d=json.load(sys.stdin); print('上传完成:', d.get('size'), '字节, SHA256:', d.get('sha256sum'))"

echo "==> 校验固件"
curl -s -b "$COOKIE" -X POST "http://$ROUTER/ubus/" -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"call\",\"params\":[\"$SID\",\"file\",\"exec\",{\"command\":\"/sbin/sysupgrade\",\"params\":[\"--test\",\"/tmp/firmware.bin\"]}]}"

echo ""
echo "==> 开始刷写（不保留配置），路由器将自动重启"
curl -s -b "$COOKIE" -X POST "http://$ROUTER/ubus/" -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"call\",\"params\":[\"$SID\",\"file\",\"exec\",{\"command\":\"/sbin/sysupgrade\",\"params\":[\"-n\",\"/tmp/firmware.bin\"]}]}" || true

echo "刷机指令已发出。等待 2~3 分钟后访问 http://$ROUTER/"
