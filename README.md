# NapCat + AstrBot QQ 机器人：部署与运维手册（脱敏分享版）

> 本手册由一次真实事故的排查过程整理而成，**已去除全部敏感信息**（IP、账号、密码、API Key、Token、WiFi、主机名等一律用 `<占位符>` 表示）。
> 保留完整步骤与技术结论，可直接照做，也可作为同类部署的参考。

---

## 目录

1. [这套系统是什么](#一这套系统是什么)
2. [架构与数据流](#二架构与数据流)
3. [工具包文件清单](#三工具包文件清单)
4. [部署步骤](#四部署步骤)
5. [关键配置](#五关键配置)
6. [服务管理](#六服务管理)
7. [⚠️ 核心经验：NapCat 启动会「抽卡」](#七️-核心经验napcat-启动会抽卡)
8. [重启验收实测记录](#八重启验收实测记录)
9. [网络与国内镜像源](#九网络与国内镜像源)
10. [故障排查速查](#十故障排查速查)
11. [踩坑总结](#十一踩坑总结)

---

## 一、这套系统是什么

用 **NapCat**（QQ 协议端，OneBot v11）接 **AstrBot**（LLM 聊天机器人框架），
把 QQ 群变成能对话的 AI 机器人，模型走 OpenAI 兼容接口（如 SiliconFlow）。

适用场景：一台长期开机的 Linux 机器（笔记本/小主机）当服务器，跑 QQ 机器人。

---

## 二、架构与数据流

```
QQ 账号 <QQ号>
   ↓ 登录
NapCat（QQ 协议端，OneBot v11，xvfb 虚拟显示无头运行）
   ↓ 反向 WebSocket  ws://127.0.0.1:6199/ws
AstrBot（aiocqhttp 适配器，机器人名 QQBot，监听 0.0.0.0:6199）
   ↓ OpenAI Compatible 协议
大模型 API（如 SiliconFlow）→ 默认模型 Qwen/Qwen2.5-7B-Instruct
```

**方向很重要（新手最容易搞反）**：
- **AstrBot 是 WebSocket 服务端**（监听 6199）
- **NapCat 是 WebSocket 客户端**（主动去连 `6199/ws`）
- 所以 WS 地址要配在 **NapCat** 的 `onebot11_<QQ号>.json` 里，**不是**配在 AstrBot 里

---

## 三、工具包文件清单

```
napcat-toolkit/
├── README.md                      ← 本文件
├── tools/                         ← 放到服务器上（如 /root/Napcat/tools/）
│   ├── config.env.example           配置模板（复制成 config.env 并填写）
│   ├── check-health.sh              一键体检【最常用】
│   ├── napcat-watchdog.sh           假死自愈看门狗（由 timer 每 30 秒调用）
│   ├── install-systemd.sh           按 config.env 渲染并安装 systemd unit
│   ├── reinstall-napcat.sh          从零重装 NapCat（全程国内镜像 + 可用离线包）
│   ├── start-napcat.sh              手动兜底启动
│   └── gh.sh                        让单条命令走本地代理访问 GitHub 官方源
├── systemd/                       ← unit 模板（含 @占位符@）
│   ├── napcat.service
│   ├── napcat-watchdog.service
│   ├── napcat-watchdog.timer
│   └── astrbot.service
└── config/
    └── onebot11.example.json      ← NapCat OneBot11 反向 WS 配置模板
```

**先做这一步**：把 `tools/config.env.example` 复制成 `tools/config.env`，填上你自己的 QQ 号、路径、端口。

---

## 四、部署步骤

以下以 root 用户、安装到 `/root/Napcat` 为例。

### 步骤 1：装系统依赖

```bash
apt-get update
apt-get install -y zip unzip jq curl xvfb screen xauth procps \
  libnss3 libgbm1 libgssapi-krb5-2 libglib2.0-0 libatk1.0-0 \
  libatspi2.0-0 libgtk-3-0 libasound2
```

> Debian 国内建议把 apt 源换成 USTC / 清华 / 阿里镜像，速度快很多。

### 步骤 2：装 QQ 本体（linuxqq）

从腾讯官方 CDN 下载 deb 安装，或直接装到 `/opt/QQ`：

```bash
# 下载地址形如（版本号以官方最新为准）：
#   https://qqdl.gtimg.cn/qqfile/QQNT/<版本>/<hash>/linuxqq_<版本>_amd64.deb
dpkg -i linuxqq_*.deb
ls /opt/QQ/qq          # 确认可执行文件存在
jq -r .version /opt/QQ/resources/app/package.json   # 记住版本号，NapCat 对版本有要求
```

### 步骤 3：把工具包放到服务器

```bash
mkdir -p /root/Napcat/tools
# 把 tools/ 下所有文件传上去（例如用 pscp / scp / rsync）
cd /root/Napcat/tools
cp config.env.example config.env
vi config.env          # 填 QQ_ACCOUNT 等
chmod +x *.sh
```

### 步骤 4：安装 NapCat

```bash
bash /root/Napcat/tools/reinstall-napcat.sh
```

该脚本做的事（**全程走国内镜像，不需要 GitHub 直连**）：
1. 经 `https://ghfast.top` 镜像下载官方安装脚本 `NapCat-Installer/script/install.sh`
2. 下载 `NapCat.Shell.zip`（约 35 MB，留一份在 `/root/napcat-offline/` 作离线包）
3. **复用已有的 `/opt/QQ`** 复制一份到 `/root/Napcat/opt/QQ`，省掉约 150 MB 重复下载
   （官方安装脚本会硬编码安装到 `$HOME/Napcat`，所以路径必须是 `$HOME/Napcat`）
4. 执行 `install.sh --docker n --cli n --proxy 0`，把 NapCat 注入到 QQ 副本的
   `resources/app/app_launcher/napcat/`，并把 `package.json` 的 `main` 改成 `./loadNapCat.js`

装完检查：

```bash
NCDIR=/root/Napcat/opt/QQ/resources/app/app_launcher/napcat
ls "$NCDIR"                       # 应看到 napcat.mjs、node_modules、config、native...
jq -r .main /root/Napcat/opt/QQ/resources/app/package.json   # 应为 ./loadNapCat.js
jq -r .main /opt/QQ/resources/app/package.json               # 应保持原样未被改动
```

### 步骤 5：写 OneBot11 反向 WS 配置

NapCat 首次启动会生成 `config/onebot11_<QQ号>.json`。把 `websocketClients` 补上：

```bash
NCDIR=/root/Napcat/opt/QQ/resources/app/app_launcher/napcat
CFG="$NCDIR/config/onebot11_<QQ号>.json"

jq '.network.websocketClients = [{
  "name":"AstrBot","enable":true,"url":"ws://127.0.0.1:6199/ws",
  "messagePostFormat":"array","reportSelfMessage":false,
  "reconnectInterval":5000,"token":"","debug":false,
  "heartInterval":30000,"verifyCertificate":true
}]' "$CFG" > "$CFG.new" && mv "$CFG.new" "$CFG"
```

> 字段名与默认值取自 NapCat.Shell 4.18.38 源码里的 `websocket-client` schema。
> **NapCat 不会热重载 OneBot 配置**，改完必须重启服务。
> 完整模板见 `config/onebot11.example.json`。

### 步骤 6：安装 systemd 服务

```bash
bash /root/Napcat/tools/install-systemd.sh
systemctl enable --now napcat astrbot
systemctl enable --now napcat-watchdog.timer
```

> `install-systemd.sh` 会把 `systemd/` 模板里的 `@NAPCAT_DIR@`、`@QQ_ACCOUNT@` 等
> 占位符按 `config.env` 替换后写入 `/etc/systemd/system/`，并自动检查是否有残留占位符。

### 步骤 7：登录 QQ

首次启动会自动生成二维码：

```bash
journalctl -u napcat -n 200 --no-pager | grep -A3 二维码
ls -la /root/Napcat/opt/QQ/resources/app/app_launcher/napcat/cache/qrcode.png
# 把 PNG 拉到本地，用手机 QQ 扫码
```

**扫码成功后，登录态会持久化在 `$HOME/.config/QQ/`**，
之后重启机器都**不需要再扫码**，会自动「快速登录」。

### 步骤 8：验证

```bash
bash /root/Napcat/tools/check-health.sh
```

期望输出里有：

```
--- NapCat <-> AstrBot 反向WS ---
正常：已连接
```

以及 AstrBot 侧日志：

```bash
journalctl -u astrbot -n 100 --no-pager | grep 适配器
# aiocqhttp(OneBot v11) 适配器已连接。
```

最后在群里发 `<唤醒词> 你好` 测 LLM 回复。

---

## 五、关键配置

### AstrBot（平台配置）

在 AstrBot WebUI → 配置文件 → 平台配置里，或用 `data/cmd_config.json`：

```json
"platform": [
  { "id": "QQBot", "type": "aiocqhttp", "enable": true,
    "ws_reverse_host": "0.0.0.0", "ws_reverse_port": 6199, "ws_reverse_token": "" }
],
"wake_prefix": ["/bot"]
```

- `wake_prefix` 是唤醒词，防止机器人对群里所有消息都回（防风控）
- `@机器人` 通常也会触发回复
- ⚠️ `cmd_config.json` **带 UTF-8 BOM**，用脚本读要用 `encoding='utf-8-sig'`

### 关键路径对照

| 组件 | 路径 | 说明 |
|---|---|---|
| NapCat 安装根目录 | `$HOME/Napcat/` | 官方脚本写死的根目录 |
| NapCat 用的 QQ 本体 | `$HOME/Napcat/opt/QQ/qq` | |
| NapCat 运行目录 | `$HOME/Napcat/opt/QQ/resources/app/app_launcher/napcat/` | napcat.mjs / config / cache |
| OneBot 配置 | `…/napcat/config/onebot11_<QQ号>.json` | |
| NapCat WebUI 配置 | `…/napcat/config/webui.json` | 含 token |
| 扫码图片 | `…/napcat/cache/qrcode.png` | |
| **QQ 登录态数据** | `$HOME/.config/QQ/` | **关键！别删，删了要重新扫码** |
| AstrBot 工作目录 | `/root/astrbot/` | 配置 `data/` |

### 获取 NapCat WebUI 地址

```bash
jq -r '"http://<主机IP>:" + (6099|tostring) + "/webui?token=" + .token' \
  /root/Napcat/opt/QQ/resources/app/app_launcher/napcat/config/webui.json
```

> 新版 NapCat（4.18.x）token 会持久化在 `webui.json`，**不再每次启动变化**。

---

## 六、服务管理

| 服务 | 作用 |
|---|---|
| `astrbot.service` | AstrBot |
| `napcat.service` | NapCat + QQ（xvfb 无头） |
| `napcat-watchdog.timer` | **假死自愈**，每 30 秒巡检一次 |

```bash
systemctl status astrbot napcat napcat-watchdog.timer --no-pager
systemctl restart astrbot napcat

journalctl -u napcat  -n 50 --no-pager    # NapCat 日志
journalctl -u astrbot -n 50 --no-pager    # AstrBot 日志
journalctl -u napcat -f                   # 实时跟踪
cat /var/log/napcat-watchdog.log          # 看门狗自愈记录

bash /root/Napcat/tools/check-health.sh   # 一键体检【最常用】
```

**不想要看门狗自动重启**（它会主动 restart napcat）：

```bash
systemctl disable --now napcat-watchdog.timer
```

---

## 七、⚠️ 核心经验：NapCat 启动会「抽卡」

**这是本手册最值钱的一节。**

### 现象

NapCat(Shell) 启动时**大约一半概率会「假死」**：

- 日志停在 `[WebUi] WebUi Token: ...` 这一行，**再也不往下走**
- 永远不会出现 `正在快速登录` / `AdapterManager` / `WebSocket反向服务`
- 进程没崩、`systemctl` 显示 **active**、NapCat WebUI 端口甚至能打开
- **但反向 WS 永远不建立，机器人实际不工作**

这就是最坑的「**服务显示正常，但机器人其实死了**」状态。

### 诊断方法

```bash
ss -tna | grep 6199                                # 没有 ESTAB 就是这个问题
journalctl -u napcat -b --no-pager | tail -5       # 卡在 WebUi Token 即确诊
ps -o pid,stat,time,etime,cmd -p <qq进程PID>       # CPU TIME 不增长 → 是死等，不是慢
cat /proc/<PID>/wchan                              # 通常是 do_sys_poll
```

### 已排除的原因（都验证过）

| 猜测 | 结论 |
|---|---|
| 系统时钟 / NTP 未同步 | ❌ `timedatectl` 显示已同步，照样卡 |
| 网络没就绪 | ❌ 卡住时已有到腾讯服务器的 ESTAB 连接 |
| 开机时序竞态 | ❌ **加 30 秒延迟照样卡**；开机 5 分钟后再重启**也照样卡** |
| 配置写错 | ❌ 同样配置，另一时刻重启就成功 |

→ 结论：**是纯随机性的启动竞态**，与配置和时序都无关。

### 解决思路：看门狗自动自愈

既然「重启能救活、成功率约 50%」，那策略就是 **发现假死就快速重试，直到连上为止**。

`napcat-watchdog.sh` 的判定与保护：

| 机制 | 说明 |
|---|---|
| 判定条件 | napcat **active** 且已运行超过宽限期（默认 90s），但 6199 **无 ESTAB** |
| 防抖 | 连续 **2 次**命中才动手，避免误判瞬时抖动 |
| 快速收敛 | 前 **5** 次重试间隔 **90s**，之后退避到 **300s** |
| 次数上限 | 单次开机最多自动重启 **12** 次，超过只记日志 |
| **扫码保护** | 日志出现 `二维码/扫码`，或 `cache/` 下有 10 分钟内的新二维码文件 → **绝不动手**（否则二维码被反复刷掉，永远登不上） |
| 计数复位 | `/run/` 下的计数文件随重启清空，所以每次开机都是全新计分 |
| 自愈记录 | `/var/log/napcat-watchdog.log` |

### 部署看门狗

```bash
# 1) 脚本已在 tools/ 里（确保可执行）
chmod +x /root/Napcat/tools/napcat-watchdog.sh

# 2) 安装 timer（install-systemd.sh 已包含）
systemctl enable --now napcat-watchdog.timer
systemctl list-timers napcat-watchdog.timer --no-pager

# 3) 手动跑一次验证（连接正常时应安静退出、不产生日志）
/root/Napcat/tools/napcat-watchdog.sh; echo "exit=$?"
```

### 重启后的合理预期

| 时间 | 应该看到 |
|---|---|
| 0～1 分钟 | SSH 可连 |
| 1～2 分钟 | `napcat` active（**可能已卡死，属正常现象**） |
| 1～4 分钟 | 若卡死，看门狗自动重启；**最迟约 4 分钟**连上 |
| 验证 | `check-health.sh` 显示「正常：已连接」 |

> **重启后机器人最多 4 分钟内自己回来，不需要人工干预。**
> 若超过 5 分钟仍未连上，手动 `systemctl restart napcat` 一次，基本一次就好。

---

## 八、重启验收实测记录

「重启后到底能不能自己回来」必须**真机重启验证**，不能只看配置。

### 第一次重启（未装看门狗）
- 两个服务都自动拉起、免扫码自动登录 ✅
- **但 NapCat 卡死，失败** ❌

### 第二次重启（装了 30 秒延迟 + 看门狗 v1）
- NapCat 仍卡死；看门狗**正确识别并自动重启**（日志有记录）✅
- 但看门狗那次也抽到卡死，且重试间隔设为 10 分钟，**收敛太慢** ⚠️
- → 据此把看门狗改成「快速重试直到连上」

### 第三次重启（看门狗 v2，全程无人干预）
```
开机
  ↓
NapCat 自启 → 抽到卡死
  ↓
看门狗第 1 次检测到假死
  ↓
看门狗确认并自动重启 NapCat
  ↓
正在快速登录 <QQ号>
WebSocket反向服务 ws://127.0.0.1:6199/ws 已启动
AstrBot: aiocqhttp(OneBot v11) 适配器已连接
```
**开机 213 秒（约 3.5 分钟）后机器人自动满血复活，全程一个命令都没敲。** ✅

### 验收用的关键手法
- 每次重启前后对比 **boot id**（`cat /proc/sys/kernel/random/boot_id`）证明真的重启了
- **全程不插手**，只轮询 `ss -tna | grep 6199`，避免自己的操作掩盖问题
- 重启前**清空看门狗日志**，保证本次自愈记录干净

---

## 九、网络与国内镜像源

### 国内网络现实

| 目标 | 结果 |
|---|---|
| `deb.debian.org`、USTC / 清华 / 阿里 apt 源 | ✅ 200 |
| `gitee.com` | ✅ 200 |
| `ghfast.top`、`ghproxy.net`（GitHub 加速） | ✅ 200 |
| **`github.com` 直连** | ❌ **超时（被墙）** |

→ 所以**默认走镜像源即可，不需要任何代理**。

### 方案 A：镜像源（推荐）

```bash
# GitHub 文件：在 URL 前面加镜像前缀
curl -fL -o out.zip "https://ghfast.top/https://github.com/<owner>/<repo>/releases/latest/download/<file>"
curl -fL -o install.sh "https://ghfast.top/https://raw.githubusercontent.com/<owner>/<repo>/main/<path>"

# PyPI
pip install -i https://mirrors.aliyun.com/pypi/simple/ <pkg>

# apt：把 sources.list 换成 USTC / 清华 / 阿里
```

### 方案 B：走本地代理（可选）

如果局域网里有一台机器跑着 Clash / FlClash 之类的代理（如 `socks5://<代理机IP>:7890`），
可以让**单条命令**走代理访问 GitHub 官方源，**不设全局代理**（避免 QQ / LLM API 流量绕远）：

```bash
./gh.sh git clone https://github.com/<owner>/<repo>
./gh.sh curl -s https://api.github.com/repos/<owner>/<repo>/releases/latest | jq -r .tag_name
```

### 常见坑：代理机防火墙没放行

如果 Debian 连不上代理机的 7890 端口，**先分清是代理没开还是被防火墙拦了**：

```bash
# 1) ARP 能通说明二层可达
ip neigh show <代理机IP>
# 2) 再测 TCP
timeout 6 bash -c 'cat < /dev/null > /dev/tcp/<代理机IP>/7890' && echo OPEN || echo BLOCKED
```

若 ARP 通、TCP 不通，多半是**代理机防火墙没放行该端口**（Windows 上尤其常见：
代理只监听 `0.0.0.0`，但**没有入站规则**）。放行时**务必只允许内网网段**：

```powershell
# Windows 示例：只允许内网网段访问 7890
New-NetFirewallRule -DisplayName "<规则名>" -Direction Inbound -Action Allow `
  -Protocol TCP -LocalPort 7890 -RemoteAddress <内网网段，如 192.168.1.0/24> -Profile Any
# 撤销
Remove-NetFirewallRule -DisplayName "<规则名>"
```

---

## 十、故障排查速查

### 0. 先跑体检

```bash
bash /root/Napcat/tools/check-health.sh
```

### 1. ⭐「服务是 active，但机器人不回话」

**最典型的故障**，八成是 NapCat 启动抽卡（见第七节）：

```bash
ss -tna | grep 6199                             # 没有 ESTAB 就是这个病
journalctl -u napcat -b --no-pager | tail -5    # 卡在 WebUi Token 即确诊
cat /var/log/napcat-watchdog.log                # 看门狗应该已经在自愈
```

处理：等最多 90 秒看门狗会自动重启；急的话手动
`systemctl restart napcat`（约 50% 一次就通，不行再试一次）。

### 2. 连接成功的标志

```bash
ss -tna | grep 6199                             # 应有两行 ESTAB（双向）
journalctl -u astrbot -n 100 --no-pager | grep 适配器
# 期望：aiocqhttp(OneBot v11) 适配器已连接。
journalctl -u napcat -b --no-pager | grep -i websocket
# 期望：WebSocket反向服务: ws://127.0.0.1:6199/ws, : 已启动
```

### 3. 报 `Unexpected server response: 405`

**原因**：OneBot WS 客户端 URL 缺 `/ws` 路径。

```bash
jq -r '.network.websocketClients' \
  /root/Napcat/opt/QQ/resources/app/app_launcher/napcat/config/onebot11_<QQ号>.json
# 正确值：ws://127.0.0.1:6199/ws
```

改完 **必须重启**：`systemctl restart napcat`。

### 4. 需要重新扫码

只有登录态失效才会发生（**正常重启不需要扫码**）。

```bash
journalctl -u napcat -n 200 --no-pager | grep -A3 二维码
ls -la /root/Napcat/opt/QQ/resources/app/app_launcher/napcat/cache/qrcode.png
# 把 PNG 下载到本地，用手机 QQ 扫
```

> 看门狗识别到扫码流程会**自动停手不打扰**，可以慢慢扫。

### 5. 日志里的「假异常」（可以无视）

- `Failed to connect to the bus ...`（dbus）
- `BuglyManager` / `NativeCrashHandler ... rqd_record.eup`
- `MESA-INTEL: warning: ... Vulkan support is incomplete`

这些都是**无桌面（无 X session / 无 dbus session）环境下的正常噪音**，不影响功能。

### 6. 端口没监听

若进程存在但端口没监听，**等 30～60 秒再看**（NapCat 启动较慢）。

### 7. 彻底重装

```bash
bash /root/Napcat/tools/reinstall-napcat.sh
systemctl restart napcat
```

---

## 十一、踩坑总结

### 坑 1（致命）：千万别把服务装到 `/tmp`

**事故经过**：上一个部署者把 NapCat 的启动器和运行目录都放在 `/tmp`
（`/tmp/launcher.sh`、`/tmp/libnapcat_launcher.so`、`/tmp/napcat/`），
而 `napcat.service` 的 `ExecStart` 指向 `/tmp/launcher.sh`。
**`/tmp` 是 tmpfs（内存文件系统），一重启全清空** → 服务 `exit 127` 无限重启，
AstrBot 还活着但失去了协议端，整个机器人瘫痪。

**教训**：
- 任何需要长期存在的东西必须放 `/root`、`/opt`、`/usr/local`
- 排查：
  ```bash
  grep -rn '/tmp' /etc/systemd/system/*.service   # 输出应无 /tmp 依赖
  ```

### 坑 2：`/opt` 里的软件不要直接改

官方 NapCat 安装方式会**复制一份 QQ** 到 `$HOME/Napcat/opt/QQ` 再注入，
**保持 `/opt/QQ` 原样**。好处是卸载干净、升级简单，出问题容易回退。

### 坑 3：登录态比你想的值钱

`$HOME/.config/QQ/` 存着 QQ 登录态。**只要它还在，重启后免扫码**。
备份/迁移时别忘了它。（反过来，它丢了就必须重新扫码。）

### 坑 4：用 SSH 工具传复杂命令会被引号坑

Windows 下用 `plink` 传含单引号、反斜杠的复杂命令时，**引号会被参数处理吃掉**，
例如 `-w "%{http_code}\n"` 变成 `200n`、`<<'PY'` 变成 `<<PY`，导致远程命令行为诡异。

**正确做法**：
```bash
# 本地写成 .sh 文件 → 传上去 → 执行
pscp -batch -hostkey <指纹> -pw <密码> local.sh root@<主机IP>:/root/x.sh
plink -ssh -batch -hostkey <指纹> -pw <密码> root@<主机IP> \
  "sed -i 's/\r$//' /root/x.sh; bash /root/x.sh"
```
注意 `sed -i 's/\r$//'` 那一步：**Windows 换行符（CRLF）会让 Linux 脚本报奇怪错误**。

### 坑 5：不要只看 `systemctl is-active`

「服务 active」**不等于**「业务正常」。这个案子里 NapCat 假死时
`is-active` 一直是 `active`，WebUI 都能打开，但机器人根本不工作。
**要按业务层探针判断**（这里是「6199 上有没有 ESTAB」），
并把它做成自动化的看门狗。

### 坑 6：重启验收必须真机做，且要「不插手」

配置写得再对，也可能有时间竞态。验收要点：
- 对比 **boot id** 确认真重启了
- **全程不手动干预**，否则掩盖问题
- 重启前清空自愈日志，保证记录干净

### 坑 7：Windows 上做内网代理，记得开防火墙入站

代理软件监听 `0.0.0.0` 不代表局域网能连——**Windows 防火墙默认拦入站**。
放行时**务必限制 `RemoteAddress` 为你自己的内网网段**，不要对公网开放。

---

## 附：本手册的脱敏说明

以下信息在整理时已全部替换为占位符，未包含任何真实数据：

| 类别 | 处理方式 |
|---|---|
| IP 地址（服务器、代理机） | → `<主机IP>`、`<代理机IP>`、`<内网网段>` |
| QQ 号 / 昵称 | → `<QQ号>`、`<机器人昵称>`（昵称已完全移除） |
| SSH 账号 / 密码 / 主机密钥指纹 | → `<用户名>`、`<密码>`、`<指纹>` |
| AstrBot WebUI 账号 / 密码 / 密码哈希 / JWT 密钥 | 全部移除 |
| NapCat WebUI Token | → `<token>`（改为用命令动态读取） |
| 大模型 API Key | 全部移除 |
| WiFi SSID / 密码 | 全部移除 |
| 主机名 / 内网拓扑细节 | 全部移除 |
| 本机 Windows 用户名与目录 | 全部移除 |
| systemd unit 中的真实路径与账号 | → `@NAPCAT_DIR@`、`@QQ_ACCOUNT@` 等占位符 + `install-systemd.sh` 渲染 |

脚本已改为从 `tools/config.env` 读取配置，因此**脱敏后仍然可以直接使用**。
