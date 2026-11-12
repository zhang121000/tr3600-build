---
name: cudy-tr3600-openwrt
description: 为 Cudy TR3600 v1 刷入/编译/配置 OpenWrt 25.12 的完整流程。涵盖：官方中间固件刷机、Docker 本地编译、GitHub Actions 云编译、PassWall 代理配置（含分流与容错）、常见故障排查。当用户需要给 Cudy TR3600 刷机、编译固件、配置代理或排查相关故障时使用。
---

# Cudy TR3600 v1 OpenWrt 完整工作流

本 Skill 来自一次完整的真机实战（2026-11-11/12），所有步骤均经过验证。

## 硬件基线

- SoC：联发科 MT7987B（双核 2.0GHz，aarch64）
- 无线：MT7990（BE3600，2.4G + 5G，Wi-Fi 7）
- 内存/闪存：512MB DDR4 / 256MB SPI-NAND
- 网口：双 2.5G（eth0=WAN/RTL8221B 外置 PHY，eth1=LAN/内置 PHY）
- 其他：USB 3.0、PWM 风扇、Reset 小孔 + 模式滑钮
- 启动：双槽位（dual-boot）U-Boot

## 阶段一：刷机（两步走）

1. 从 Cudy 官方下载中心下载 `Develop_files_for_TR3600.zip`，解压出中间固件
   - https://www.cudy.com/zh-cn/pages/download-center/tr3600-1-0
2. 原厂后台 `192.168.10.1` → 固件升级 → 刷入中间固件（Cudy 签名，可从原厂界面直接刷）
3. 中间固件 LuCI `192.168.1.1` → 系统 → 备份/升级 → 上传目标 sysupgrade 固件，**取消保留配置** → 刷入
4. 刷机前务必备份原厂分区（BL2/Factory/bdinfo/FIP），Factory 含无线校准数据

## 阶段二：编译（两条路线任选）

### 路线 A：GitHub Actions 云编译（推荐新手）

使用本仓库的 `.github/workflows/build.yml`，fork 后手动触发即可。约 1~2 小时。

### 路线 B：本地 Docker 编译（推荐有 Docker 的 Mac/Linux）

- Ubuntu 24.04 容器，挂载工作目录
- 必须加 `--cap-add MKNOD`（否则 tar 的 configure 失败）
- 必须 `export FORCE_UNSAFE_CONFIGURE=1`（容器内 root 编译）
- 必须 `export GOPROXY=https://goproxy.cn,direct`（国内网络）
- **在容器原生文件系统编译**（macOS 挂载目录不区分大小写，OpenWrt 拒绝编译）
- ARM64 主机需预装官方 Go 并配置 `CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT`（见 config.seed）
- 用 `scripts/build.sh`（本仓库 skill/scripts/ 下有参考实现）

## 阶段三：配置

### 基础配置

- LAN 网段已预置为 `192.168.2.1`（避开光猫 `192.168.1.1`），**不要在运行时通过 uci 修改 LAN 网段**（会卡死系统，见 pitfalls）
- Wi-Fi 默认关闭，后台开启即可。建议 2.4G 固定信道 6、5G 固定信道 36 + 80MHz
- 时区 Asia/Shanghai

### PassWall 代理配置

1. 订阅管理 → 添加订阅链接 → 更新订阅导入节点
2. **新版 PassWall 主节点字段是 `node`**（不是老教程的 `tcp_node`），只设后者会导致主代理不启动
3. 分流：编辑"分流总节点"（myshunt），AIGC 规则（geosite:category-ai-!cn）指向原生 IP 节点，default_node 指向日常节点
4. 容错：创建 Xray `_balancing` 协议节点（负载均衡组），把多个节点加入 balancing_node，设置 fallback_node 兜底；可把不同机场的节点混编入组实现跨机场容错
5. 启动前确认 geosite.dat/geoip.dat 存在（本固件已预置在 /usr/share/v2ray/）

## 故障排查决策树

- **网口突然死亡/100%丢包** → RTL8221B EEE bug（本固件已修复）。参见 reference/pitfalls.md
- **改 LAN 网段后系统卡死** → 已知问题，用预置法绕过（本固件已预置）
- **xray 启动失败** → 检查 geosite.dat 是否存在（日志里搜 geodata）
- **代理配好了但不通** → 检查是否用了 `node` 字段；逐节点 tcping + openssl SNI 握手测试
- **所有节点握手失败但 TCP 通** → 节点被宽带/运营商拦截或节点本身死了，换节点或换机场
- **Mac 能上国内不能上国外** → 检查是否同时开了客户端代理（FlClash/Clash）与路由器 PassWall 双重代理冲突
- **完全失联** → Reset 长按 10 秒恢复出厂（预置配置在固件里，恢复后仍是完整状态）

## 参考文件

- `scripts/build.sh` — Docker 本地编译脚本
- `scripts/flash.sh` — 刷机自动化（LuCI 上传 + sysupgrade）
- `scripts/ssh-helper.exp` — SSH 密码交互助手
- `reference/pitfalls.md` — 完整踩坑记录
