# 事故复盘：OpenClash 配置改崩的几次

> 记录 2026-11-20/21 的连续故障。目的不是道歉，是让下一个人（或下一次的我）不再犯。
> 每条都写明：现象 → 根因 → 正确做法。

## 事故清单

### 1. `uci set` 把列表写成了带空格的字符串

- **现象**：PassWall 重启失败，`util_sing-box.lua: ut_node_id (a nil value)`，sing-box 没起来，全屋断网。
- **根因**：`uci set passwall.UTFAST.urltest_node="a b c"` 把列表写成了一个 option。生成器按 list 遍历，拿到 nil。
- **正确做法**：列表类型必须 `uci delete` 后逐条 `uci add_list`；改完 `uci show` 确认是 `'a' 'b' 'c'` 形式。

### 2. 把 Xray 节点塞进 sing-box 的 urltest 组

- **现象**：PassWall 生成配置直接崩。
- **根因**：组是 `type=sing-box`，成员必须是 sing-box 节点；Xray 节点只能单独绑定（走 nodesocks）。
- **正确做法**：加组前先查 `uci get passwall.<id>.type`；混类型一律拒绝。

### 3. 重写 YAML 的 `dns:` 段漏了 `listen`

- **现象**：所有设备 DNS 超时，百度/Apple/Google 全 000。
- **根因**：OpenClash 的 dnsmasq 把 53 转发到 `127.0.0.1:7874`，而新的 dns 段没写 `listen: 0.0.0.0:7874`，内核根本没监听。
- **正确做法**：任何自定义 dns 段必须包含 `listen`（默认 7874）；改完先 `netstat -ltnu | grep 7874` 再热加载。

### 4. `respect-rules: true` + DNS 绑定代理组 = 解析回环

- **现象**：百度、Apple、Google 一起超时；日志 `dns resolve failed: context deadline exceeded`。
- **根因**：开了 `respect-rules`（DNS 查询也走分流），又把 Google 域名的 DNS 指到 `#GOOGLE` 代理组；而连代理要先解析节点域名，形成“解析需要代理、代理需要解析”的死循环。
- **正确做法**：不要用 `respect-rules` 搭配 `#组名` 的 DNS。需要代理侧解析时，用 `proxy-server-nameserver`；需要国内解析用 `nameserver`（doh.pub/alidns），国外用 `fallback`（tls://8.8.4.4）。DNS 段不引用任何代理组最稳。

### 5. 删了代理组，DNS 里还留着 `#组名`

- **现象**：非国内域名全部解析失败，Play CDN、部分网页加载不出来。
- **根因**：DNS 里写的是 `https://1.1.1.1/dns-query#nvenix`，后来把 `nvenix` 组删了，引用失效，DoH 无法连接。
- **正确做法**：删组/改名时全局搜索 `#<组名>`；或者 DNS 永远不写 `#组名`。

### 6. 直接在生产的 `/etc/openclash/RAK.yaml` 上改

- **现象**：连续三次把全屋网络改挂，每次都要等用户切回 LAN 才能救。
- **根因**：没有先在临时实例验证，改完直接热加载。
- **正确做法（硬规则）**：
  1. 改动只写 `/tmp/xxx.new`；
  2. `SAFE_PATHS=/usr/share/openclash mihomo -t -d /etc/openclash -f /tmp/xxx.new` 必须通过；
  3. 起临时实例（另开 7994/9094），实际请求验证 DNS + 百度 + Apple + Google；
  4. 再 `cp` 到生产 + `PUT /configs?force=true` 热加载；
  5. 加载后立刻验证三项，失败一条命令回滚（备份放 `/root`，不要放 `/tmp`）。

### 7. fake-ip 下用 `GEOIP,CN,DIRECT` 判 CDN

- **现象**：Google Play 下载一直 0%，页面能开。
- **根因**：Play 的下载域名（`rr*.xn--ngstr-lra8j.com`）解析到中国移动的 Google 缓存 IP；`GEOIP,CN,DIRECT` 把它判成国内直连，而该 IP 的 443 在家宽上不可达；改走代理后，签名 URL 又与出口 IP 不匹配，CDN 不给数据。
- **正确做法**：CDN 域名用**域名规则**控制（不用 GEOIP）；Play 下载在代理环境下本身就是坑，别承诺能修，直接建议手机流量或 APK 镜像站。

### 8. 在路由器上起第二个 mihomo，忘了它会再被主代理劫持

- **现象**：所有“隧道测速”只有 15 Mbps，实际能到 100 Mbps。
- **根因**：OpenClash 的 `nat_output → redirect :7892` 会劫持路由器自身的 TCP 出站；测试实例的出站又被套了一层主代理，变成双层代理。
- **正确做法**：测隧道吞吐时，要么临时在 `nat_output` 给目标 IP 加 `return`（测完删除），要么直接在被测服务器上跑测速；并且用 `mihomo` 的 `/connections` 看真实字节数。

## 操作纪律（写死）

1. **生产配置只读**：所有修改先在 `/tmp` 生成 + 临时实例验证。
2. **改完必须验证三件**：DNS（`nslookup baidu`）、国内（`curl baidu`）、国外（`curl gstatic`）。
3. **备份到 `/root`**，文件名带时间；回滚命令提前写好。
4. **一次只改一类**（DNS / 规则 / 节点 / UCI），改完验证再动下一类。
5. **DNS 段不引用代理组**，不轻易开 `respect-rules`。
6. **列表用 `uci add_list`**，不用 `uci set` 写空格字符串。
7. **组和节点类型要匹配**：sing-box 组只放 sing-box 节点。
8. 出问题先让用户切回路由器 LAN（`192.168.2.x`），手机热点救不了 LAN 访问。
