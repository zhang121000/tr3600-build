# sing-box 单架构运行时（TR3600 实测）

本文记录 2026-11-14 在 Cudy TR3600 v1（512MB 内存）上，把 PassWall 从“Xray 分流 + 每个 AnyTLS 节点一个 sing-box 进程”迁移到“sing-box 单架构 + URLTest”的完整方案。

## 为什么要迁移

PassWall 的 Xray 主分流不支持 AnyTLS。把 AnyTLS 节点放进 Xray `_balancing` 组时，PassWall 会为**每个节点**启动一个 sing-box socks 进程，再交给 Xray 使用。

- 50 个节点 → 38 个代理进程 → 387MB 内存、负载 15，路由器卡死
- 这是进程模型问题，不是节点或硬件故障

## 目标架构

```
sing-box 主进程（_shunt）
├── UTFAST    日常：香港 9 个普通节点（URLTest）
├── UTGOOGLE  Google：新加坡节点（URLTest）
├── UTSTREAM  流媒体：香港节点（URLTest）
├── UT10X     10x 高速：台/澳/港/日 ×10（URLTest）
├── UTDAILY   手动 broad：港澳日台新批量匹配
└── AIGC      ChatGPT / Claude：固定台湾原生 IP（单节点）

另有一个 xray 进程：仅用于 AIGC 原生节点（PassWall 会把它转成 socks）
```

实测：**2 个进程 / 约 145MB 内存**，可承载 30+ 个 AnyTLS 节点。

## 关键前提：同内核铁律

池成员、池本身、分流总节点，三者必须同内核：

- AnyTLS（sing-box）→ sing-box 主分流 + `_urltest`
- VLESS（Xray）→ Xray 主分流 + `_balancing`
- 在 Xray 主分流下创建 `_urltest`，PassWall 仍会把子节点拆成单独进程；必须把 `myshunt.type` 改成 `sing-box` 才真正生效
- 混用会构建不出出口，甚至回落直连

## 配置步骤

1. 备份 `/etc/config/passwall`
2. 确认 `sing-box`、`geoview` 已安装；PassWall 25.3.9+ 的 sing-box 分流依赖 Geoview
3. 建 `_urltest` 节点（类型 sing-box，协议 `_urltest`）：
   - `node_add_mode=manual` + `urltest_node` 列表，或
   - `node_add_mode=batch` + `node_group` + `node_match_rule`（订阅更新自动进组）
4. 建新的 `_shunt` 节点（类型 sing-box，协议 `_shunt`），把规则指向各 URLTest 组
5. 把 `passwall.@global[0]` 的 `node` / `tcp_node` / `udp_node` 指向新的 shunt
6. 重启 PassWall，验证进程数、内存、Google/ChatGPT/YouTube
7. 失败回滚：把上述三个字段指回旧 shunt，重启

## URLTest 参数建议

| 组 | interval | tolerance | interrupt_exist_connections |
|---|---|---|---|
| 日常（同地区） | 10m | 200ms | 0 |
| Google / 流媒体 | 10m | 150ms | 0 |
| 10x 高速 | 5m | 100ms | 0 |
| 大池 broad | 10m | 200ms | 0 |

- `interval` 是探测频率，不是切换频率
- `tolerance` 是反抖动阈值：新节点必须快出该值才切
- `interrupt_exist_connections=0`：切换不打断已有连接，减少 YouTube/Twitter 重连
- URLTest 不会在主节点恢复后切回，也不做多出口分担
- URLTest 按延迟选，不按带宽选；延迟低但带宽差的节点仍可能被选中，因此日常组应精选节点并固定同地区

## IP 稳定性

- 日常固定香港、Google 固定新加坡、流媒体固定香港、AI 固定台湾原生 IP
- 需要跨地区切换时，用 `pw-mode.sh broad` 手动切，不要让日常池跨国家跳
- 对账号敏感的服务（AI、银行）用单节点 + 后备，不要进 URLTest

## 自动切换

路由器时区必须先设为 `Asia/Shanghai`（默认可能是 GMT0，会导致 cron 错 8 小时）：

```sh
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci commit system
/etc/init.d/system reload
```

cron：

```cron
0 20 * * * /root/pw-mode.sh boost
0 23 * * * /root/pw-mode.sh normal
```

`pw-mode.sh` 切换后会测 Google，失败自动回退到上一个模式，日志在 `/root/pw-mode.log`。

## 资源数据（TR3600 v1）

| 项目 | Xray 双架构（13 进程） | sing-box 单架构（2 进程） |
|---|---|---|
| 进程 | 13 | 2 |
| 内存 | 235MB | 145MB |
| 日常速度 | 30~90 Mbps | 50~90 Mbps |
| 10x boost | — | 约 74 Mbps |

## 常见问题

### IPv6-only 节点全部超时

`SBV6`、`CMIN2 V6` 等节点域名只有 AAAA 记录。若路由器 WAN 没有全局 IPv6（只有 `fe80::`），`ping6` 会 `Network unreachable`，节点不可用。先查 `nslookup 域名` 和 `ip -6 route`，确认有 IPv6 再放入组。

### 切换后没有网络

`pw-mode.sh` 会测试 Google，失败自动回退。若手动改配置，检查：

1. `myshunt.type` 是否与节点内核一致
2. URLTest 组是否真的有可用节点
3. `geoview` 是否存在，规则是否生成
4. DNS 是否正常（`nslookup google.com`）

### 进程数没有下降

如果主分流仍是 Xray，`_urltest` 不会合并子节点进程；必须把主分流类型改为 sing-box。
