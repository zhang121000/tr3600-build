# OpenWrt 25.12 for Cudy TR3600 v1

为 Cudy TR3600 v1（联发科 MT7987B + MT7990 Wi-Fi 7）提供的 OpenWrt 25.12 云编译方案与成品固件。

> ⚠️ 实验性项目：设备支持基于尚未合并的上游 PR（[openwrt/openwrt#24596](https://github.com/openwrt/openwrt/pull/24596)，作者 soapman），并叠加了网口 EEE 修复。刷机有风险，请自行承担。

## 固件特性

- 中文 LuCI 界面（含插件中文翻译）
- PassWall 全家桶：xray-core / sing-box 双内核、chinadns-ng、Haproxy 负载均衡
- Adblock 去广告、DDNS、WireGuard / OpenVPN
- USB 存储（UAS 加速）+ KSMBD 文件共享
- 风扇 PWM 温控、UPnP、WOL、ttyd 网页终端
- 预置 LAN 网段 `192.168.2.1`（避免与光猫 `192.168.1.1` 冲突）
- 预置 geosite.dat / geoip.dat（xray 分流必需）

## 刷机教程

1. 从 [Cudy 官方下载中心](https://www.cudy.com/zh-cn/pages/download-center/tr3600-1-0) 下载 `Develop_files_for_TR3600.zip`，解压出其中的**中间固件**（Intermediate firmware）
2. 原厂后台 `192.168.10.1` → 固件升级 → 刷入中间固件，等待重启
3. 中间固件后台 `192.168.1.1` → 系统 → 备份/升级 → 上传本项目的 sysupgrade 固件，**取消勾选"保留配置"**，刷入
4. 重启后管理地址为 `http://192.168.2.1`（root，无密码，请立即设置）

### 启用 Wi-Fi

Wi-Fi 默认关闭（OpenWrt 惯例）。进入后台 → 网络 → 无线 → 编辑两个频段，设置 SSID/密码并启用。建议：2.4G 固定信道 6，5G 固定信道 36 + 80MHz 频宽。

### 配置代理

服务 → PassWall → 订阅管理 → 添加你的订阅链接 → 更新订阅 → 在主节点中选择节点即可。新版 PassWall 主节点字段为 `node`（不再使用老教程中的 `tcp_node`）。

## 实测数据（TR3600 v1 真机验证）

| 项目 | 实测 |
|---|---|
| 内存占用（全开插件） | 134MB / 498MB（27%） |
| 满载温度 | 48°C（风扇 PWM 自动温控） |
| 代理吞吐（优质中转节点） | 30 Mbps+ |
| Wi-Fi 双频 | 2.4G / 5G 均正常 |
| 有线网口 | 双 2.5G 正常（已修复 EEE 问题） |

## 踩坑记录（本项目独家经验）

1. **RTL8221B 网口 EEE Bug**：在 100M/1G 链路上协商 EEE 后会出现 100% 丢包、链路死亡。已通过在 DTS 中添加 `eee-broken-100tx` / `eee-broken-1000t` 修复（参见上游 [PR #25996](https://github.com/openwrt/openwrt/pull/25996)）
2. **运行时修改 LAN 网段会导致系统卡死**：本项目通过将目标网段预置进固件（files/overlay）的方式规避，请勿在运行时通过 uci 直接修改 LAN 网段
3. **新版 PassWall 主节点字段为 `node`**：老教程中的 `tcp_node` 已不被识别
4. **xray 启动需要 geosite.dat**：缺失会导致启动失败，本固件已预置
5. **首次使用请先联网再启用插件**（PassWall / adblock 首次启动需要下载规则）

## 云编译

Fork 本仓库 → Actions → 手动触发 `Build OpenWrt 25.12 for Cudy TR3600 v1` → 编译完成后在 Artifacts 中下载固件。全程约 1~2 小时（GitHub 免费 runner）。

## 致谢

- 设备支持补丁：[soapman 的上游 PR](https://github.com/openwrt/openwrt/pull/24596)
- EEE 修复参考：[openwrt/openwrt#25996](https://github.com/openwrt/openwrt/pull/25996)
- PassWall：[Openwrt-Passwall](https://github.com/Openwrt-Passwall/openwrt-passwall)

## 免责声明

本项目与 OpenWrt 官方、Cudy 官方无关。固件为实验性质，刷机风险自负。请在刷机前备份原厂分区（特别是 Factory 无线校准分区）。
