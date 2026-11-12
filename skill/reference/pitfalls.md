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

机场节点会挂（尤其普通线路）。应对：建 Xray `_balancing` 容错组，把多个节点编入，设置 fallback_node。可跨机场混编实现服务商级容错。
