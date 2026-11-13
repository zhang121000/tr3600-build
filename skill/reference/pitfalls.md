# TR3600 实战踩坑记录（2026-11-11/12 真机验证）

## 1. RTL8221B 网口 EEE Bug（上游已确认）

**症状**：100M/1G 链路下网口突然死亡、100% 丢包，2.5G 正常。看起来"很随机"。

**根因**：RTL8221B PHY 与对端协商 EEE（节能以太网）后链路死亡。上游实测 TR3600 v1 在 EEE active + TX LPI on 时 100% 丢包。

**修复**：DTS 中给 PHY 加 `eee-broken-100tx; eee-broken-1000t;`（见本仓库 patches/0002）。
上游参考：https://github.com/openwrt/openwrt/pull/25996

## 2. 运行时修改 LAN 网段导致系统卡死

**症状**：uci 改 LAN IP（如 192.168.2.1）后重启网络/重启整机，整个网络栈卡死：有线不应答、Wi-Fi 能搜到但连不上、DHCP 不工作。恢复出厂后正常。

**对策**：**不要运行时改 LAN 网段**。把目标网段预置进固件（files/etc/config/network），开机即是目标网段，绕过此问题。本仓库已预置 192.168.2.1。

## 3. 新版 PassWall 主节点字段为 `node`

**症状**：按老教程只设 `tcp_node`/`udp_node`，防火墙规则加载了但 xray 主程序不启动。

**根因**：新版 PassWall 用 `@global[0].node` 作为主节点字段（CBI 里的"代理节点"下拉）。只设 `tcp_node` 时 `ENABLED_DEFAULT_ACL=0`，主代理不启动。

**修复**：`uci set passwall.@global[0].node='myshunt'`（或你的分流节点）。

## 4. xray 启动失败：缺 geosite.dat

**症状**：日志报 `failed to open geosite.dat`，xray 无法启动。

**根因**：分流规则引用 geosite 类别（如 geosite:category-ai-!cn），但 geosite.dat 数据文件缺失。

**修复**：下载 Loyalsoldier 的 geosite.dat + geoip.dat 放入 /usr/share/v2ray/。本固件已预置。注意：恢复出厂会清掉 overlay 里的文件，烧进固件最保险。

## 5. Docker 编译 OpenWrt 的坑（ARM64 Mac）

- `tools/tar` configure 失败：容器缺 MKNOD 权限 → 加 `--cap-add MKNOD`；root 身份被拒 → `export FORCE_UNSAFE_CONFIGURE=1`
- `golang-bootstrap` 不支持 linux/arm64 → 装官方 Go 二进制，设 `CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT="/usr/local/go"` 且 `# CONFIG_GOLANG_BUILD_BOOTSTRAP is not set`
- Go 模块下载被墙 → `export GOPROXY=https://goproxy.cn,direct`
- macOS 挂载目录不区分大小写 → 必须在容器原生文件系统编译
- Rust 组件（shadowsocks-rust）编译 LLVM 会 OOM → 如不需要就禁用（纯 VLESS 订阅用不上）

## 6. 客户端与路由器双重代理冲突

**症状**：Mac 上开着 FlClash/Clash 客户端，同时路由器跑 PassWall，ChatGPT 等对连接敏感的服务挂掉。

**对策**：在家用路由器，客户端退出或关闭系统代理+TUN；出门在外才用客户端。

## 7. 节点部分死亡是常态

机场节点会挂（尤其普通线路）。应对：建容错组，把多个节点编入；Xray 节点用 `_balancing`，AnyTLS 节点用 sing-box `_urltest`。可跨机场混编实现服务商级容错。

## 8. Xray 分流 + AnyTLS：一个节点一个 sing-box 进程

**症状**：PassWall 的均衡组里放几十个 AnyTLS 节点后，路由器突然卡死，SSH/LuCI 无响应，内存接近耗尽，负载 15+。

**根因**：Xray 不支持 AnyTLS，PassWall 会为均衡组里的**每个 AnyTLS 节点**单独启动一个 sing-box socks 进程。50 个节点 ≈ 30~40 个进程，512MB 内存扛不住。

**修复**：AnyTLS 节点改用 **sing-box 主分流 + `_urltest`**，所有节点在一个 sing-box 进程内。实测进程数从 13 降到 2，内存从 235MB 降到 145MB。

## 9. 同内核铁律：池成员、池、分流总节点必须同内核

**症状**：把 Xray 负载均衡组塞进 sing-box 的 `_urltest`，或反过来，组里明明有节点却不生效，甚至回落直连。

**根因**：PassWall 的组/分流总节点有内核绑定；跨内核调用构建不出出口。

**对策**：

- AnyTLS / sing-box 节点 → sing-box 主分流 + `_urltest`；
- VLESS 等 Xray 节点 → Xray 主分流 + `_balancing`；
- 混合协议时，要么把节点类型统一成 sing-box，要么按内核拆成独立链路。
- 注意：在 Xray 主分流下创建 `_urltest`，PassWall 仍会把子节点拆成单独 socks 进程；必须把 `myshunt.type` 改成 `sing-box` 才真正生效。

## 10. URLTest 的 interval ≠ 切换频率

**症状**：担心 `interval=3m` 会导致每 3 分钟跳一次 IP。

**事实**：`interval` 是探测频率；只有当另一个节点比当前节点快出 `tolerance`（默认 50ms）时才会切换。AnyTLS 冷启动延迟偏高，50ms 容差容易抖，建议 150~200ms、探测 10 分钟。URLTest 还**不会在主节点恢复后切回**，也不做多出口分担。

## 11. IPv6-only 节点在纯 IPv4 网络不可用

**症状**：`SBV6`、`CMIN2 V6` 等节点全部超时，但节点本身没坏。

**根因**：这些域名只解析出 AAAA（IPv6），而路由器 WAN 只有 IPv4/链路本地 IPv6，`ping6` 直接 `Network unreachable`。

**排查**：`nslookup 节点域名` 看是否有 A 记录；`ip -6 route` 看是否有全局 IPv6 默认路由。没有 IPv6 就不要再把这类节点放进组里。

## 12. 路由器默认时区可能是 GMT，cron 会错 8 小时

**症状**：cron 写 `0 20 * * *`，实际凌晨 4 点才执行。

**根因**：系统 `timezone='GMT0'`，不是 `Asia/Shanghai`。

**修复**：

```sh
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci commit system
/etc/init.d/system reload
```

## 13. sing-box 分流依赖 Geoview

PassWall 25.3.9 之后，sing-box 分流需要 Geoview 把 geosite/geoip 转成 rule-set。缺少 Geoview 时，节点能连但分流规则不生效。排查：`which geoview`、`sing-box version`、`logread -e geoview`。
