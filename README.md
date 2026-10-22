# PcMate iOS

PcMate 的 iOS 原生客户端，使用 SwiftUI 编写，协议与 Android 版、PcMate Agent 1.2.0 兼容（旧版 Agent 仍可连接，只是缺文件接口和详情面板）。

没有 Mac 也能构建：工程通过 XcodeGen 生成，在 GitHub Actions 或 Codemagic 的 macOS runner 上编译出**未签名 ipa**，再用「全能签 / ESign」重签安装到 iPhone。

---

## 功能

- **两种连接方式**
  - Agent：WebSocket 实时快照 + HTTPS 文件接口，推荐方式。
  - SSH：Citadel / SFTP 回退，适合没有运行 Agent 的电脑。
- **配对**
  - 电脑端 Agent 生成 6 位配对码，iOS 输入后交换访问令牌。
  - 首次连接采用 TOFU：记录服务器证书 SHA-256 指纹，后续指纹不一致会拒绝连接。
  - SSH 主机密钥同样按 SHA-256 指纹固定。
- **仪表盘**
  - 顶部概要卡 + 2×3 均等卡片网格（统一大小）：第一行 处理器 / 内存，第二行 网络 / 显卡，第三行 运行时间 / 进程。
  - 每个卡片都能点开详情面板：
    - 处理器：每个逻辑核心的实时占用条、频率、核心数，可跳到进程列表。
    - 内存：已用/可用/缓存/提交/交换/分页池明细，可一键整理内存。
    - 网络：上下行速率与累计流量、延迟、网卡列表、Wi-Fi（SSID/信号/频段/信道/速率）、蓝牙设备与连接状态。
    - 显卡：占用率、显存、显卡列表（型号/厂商/驱动/状态）。
    - 运行时间：开机时间、系统与连接信息，可一键重连。
  - Agent 模式实时推送；SSH 模式按设定间隔采样。
- **进程管理**
  - 中文进程名与分组、图标、CPU / 内存排序、搜索、结束进程。
- **文件传输**
  - 浏览磁盘与目录、进入/返回、搜索。
  - 上传手机文件、下载到「文件」App、新建文件夹、删除文件/空目录。
  - Agent 走 HTTPS 文件接口；SSH 走 SFTP。
- **清理**
  - Linux：页缓存 / 目录缓存 / 组合清理 / 深度整理。
  - Windows：工作集整理（EmptyWorkingSet）。
- **安全存储**
  - 密码、私钥、Agent 令牌、证书/主机指纹保存在 iOS Keychain。
  - UserDefaults 只保存连接元数据。

---

## 环境要求

| 项目 | 要求 |
| --- | --- |
| iPhone | iOS 16.4 或更高 |
| 电脑端 | PcMate Agent 1.2.0（Windows / Linux），或开启 OpenSSH 服务 |
| 网络 | iPhone 与电脑在同一局域网 |
| 构建 | macOS + Xcode 15.4（云端 runner 已满足） |
| 构建工具 | XcodeGen **2.38.0**（脚本会自动安装固定版本） |

> 不要在 Xcode 15.x 上使用 XcodeGen 2.42+：它会写出 objectVersion 77，Xcode 15 打不开。仓库里的 `scripts/install-xcodegen.sh` 已锁定 2.38.0。

---

## 目录结构

```
PcMateIOS/
├── project.yml                  # XcodeGen 工程定义（SPM 依赖、Info.plist、scheme）
├── codemagic.yaml               # Codemagic 云端构建
├── .github/workflows/
│   └── ios-build.yml            # GitHub Actions 云端构建
├── scripts/
│   ├── install-xcodegen.sh      # 安装固定版本 XcodeGen
│   ├── build-unsigned-ipa.sh    # 编译 + 打包未签名 ipa
│   ├── publish-github.ps1       # Windows 无 git 发布到 GitHub 并取回 ipa
│   └── inspect-ipa.ps1          # Windows 本地验包
└── PcMate/
    ├── App/                     # App 入口
    ├── Models/                  # 数据模型、连接持久化、进程目录
    ├── Net/                     # Agent / SSH / TLS / 配对 / 会话控制
    ├── Theme/                   # Aurora UI token
    ├── UI/                      # 首页、连接、仪表盘、进程、文件、清理
    └── Resources/               # Assets.xcassets、AppIcon
```

---

## 电脑端准备

### 1. 安装并启动 Agent

Windows 默认路径：

```
C:\Program Files\PcMate\pcmate-agent.exe
```

确认服务在运行：

```powershell
Get-Service PcMateAgent
curl.exe -k https://127.0.0.1:8765/health
```

应返回类似：

```json
{"status":"ok","version":"1.2.0"}
```

### 2. 配对新设备

在电脑端 PcMate Agent 托盘菜单里选择「配对新设备」，会显示 6 位配对码，5 分钟内有效。

### 3. SSH 回退（可选）

如果要使用 SSH 模式，需要在电脑上开启 OpenSSH Server，并知道：

- 电脑 IP / 主机名
- SSH 端口（默认 22）
- 用户名
- 密码，或 OpenSSH 私钥（ed25519 / RSA）

---

## 构建未签名 ipa

### 方式 A：GitHub Actions（推荐）

1. 把 `PcMateIOS` 目录内容推到 GitHub 仓库根目录。
2. 仓库 → **Actions** → 左侧 **Build iOS (unsigned ipa)** → **Run workflow**。
3. 等待 macOS runner 完成（通常 3~6 分钟）。
4. 在 Run 页面底部下载 artifact **PcMate-unsigned-ipa**。
5. 解压后得到 `PcMate-unsigned.ipa` 和 `Info.json`。

公开仓库的 Actions 分钟数免费；私有仓库会消耗 macOS 分钟数。

### 方式 B：Codemagic

1. 把工程推到 GitHub。
2. Codemagic → **Add app** → 选择仓库。
3. 首次构建会自动读取 `codemagic.yaml`。
4. 构建完成后在 **Artifacts** 下载 `PcMate-unsigned.ipa`。

### 方式 C：Windows 一条命令发布 + 构建 + 下载

本机不需要安装 git。准备一个 GitHub PAT（classic token，勾选 `repo` + `workflow`），然后：

```powershell
cd C:\Users\Admin\Documents\默认项目\PcMateIOS
powershell -ExecutionPolicy Bypass -File scripts\publish-github.ps1 -Token "ghp_xxx"
```

脚本会：

1. 验证 PAT；
2. 创建或复用 `<用户名>/PcMate-iOS` 仓库；
3. 通过 Git Data API 上传文件；
4. 触发 `ios-build.yml`；
5. 轮询构建；
6. 把 ipa 和 Info.json 下载到 `build\`。

可选参数：

```powershell
# 私有仓库
... -Private

# 只推代码，不触发构建
... -SkipBuild

# 自定义仓库名
... -RepoName "PcMate-iOS"
```

### 本地验包（Windows）

```powershell
powershell -ExecutionPolicy Bypass -File scripts\inspect-ipa.ps1
```

检查项：

- zip 结构是否为 `Payload/PcMate.app`
- Bundle ID / 版本 / 最低系统版本
- 主可执行文件是否 Mach-O arm64
- 是否确实未签名（没有 `_CodeSignature` / `embedded.mobileprovision`）

---

## 用全能签安装

1. 把 `PcMate-unsigned.ipa` 传到 iPhone（AirDrop / 文件 App / 局域网传输均可）。
2. 打开「全能签」，选择 **导入 ipa**。
3. 选择自己的签名证书（个人证书 / 企业证书）。
4. 修改 Bundle ID（如果证书要求），保持 `PcMate` 名称。
5. 点击签名，完成后安装。
6. 首次打开如果提示「未受信任的开发者」，到 **设置 → 通用 → VPN 与设备管理** 信任证书。

> 未签名 ipa 不能直接安装；必须经过重签。证书和描述文件由你自己的 Apple ID / 证书提供。

---

## 使用流程

1. 打开 PcMate iOS。
2. 点「添加第一台电脑」。
3. 填写名称、电脑 IP，连接方式选 **Agent**。
4. 点「用 6 位配对码连接」，输入电脑端显示的 6 位数字。
5. 配对成功后保存，回到首页点电脑卡片。
6. 仪表盘连接成功后，可进入：
   - **进程**：查看/搜索/结束进程；
   - **文件**：浏览、上传、下载、新建文件夹、删除；
   - **清理**：选择清理方式并执行。

Agent 连接失败且已填写 SSH 信息时，会自动回退 SSH（可在连接编辑页关闭）。

---

## 常见问题

### 连接失败 / 一直转圈

- 确认 iPhone 和电脑在同一 Wi-Fi，且没有开启 AP 隔离。
- 确认电脑防火墙允许 Agent 端口（默认 8765）和 SSH 端口（默认 22）。
- 用电脑浏览器打开 `https://<电脑IP>:8765/health`，先排除 Agent 本身的问题。
- 如果之前配对过但电脑重装了 Agent，证书指纹会变化，需要删除旧连接重新配对。

### 提示证书指纹不一致

这是 TOFU 保护：服务器证书变了。确认是你自己重装/更换了 Agent 证书，然后删除连接重新配对；不要在不明网络环境下忽略此提示。

### 文件页显示 “404 page not found”

电脑上的 Agent 版本太旧（1.0.x 没有 `/files/*` 接口）。把电脑端 Agent 升级到 **1.2.0** 后再进文件页：

```powershell
# 管理员 PowerShell
sc.exe stop PcMateAgent
Copy-Item .\pcmate-agent-windows-amd64.exe "C:\Program Files\PcMate\pcmate-agent.exe" -Force
sc.exe start PcMateAgent
```

升级不会更换令牌和证书，手机端不需要重新配对。可以用 `https://<电脑IP>:8765/health` 确认版本已变成 1.2.0。

### 详情面板里网络 / 显卡显示“需要 Agent 1.2.0”

同样是 Agent 版本问题：`netinfo`、`gpuinfo`、`sysinfo` 是 1.2.0 新增接口。旧版 Agent 仍可正常看仪表盘、进程、文件和清理。

### 文件下载后在哪里

下载文件保存在 App 沙盒的 `Documents/Downloads`，下载完成后会弹出系统「存储到文件」面板，可保存到「文件」App 或 iCloud Drive。

### SSH 模式无法浏览 Windows 磁盘

Windows OpenSSH 的 SFTP 根路径通常是 `C:/`。App 会自动从 `C:/` 开始；如果权限不足，请确认 SSH 用户有对应目录的读取权限。

### 构建报 “future Xcode project file format (77)”

XcodeGen 版本太新。执行：

```bash
bash scripts/install-xcodegen.sh
```

脚本会安装 2.38.0。

### 构建报 SPM 依赖解析失败

确认 `project.yml` 中的版本没有被改动：

- Citadel `0.11.0`
- swift-nio-ssh `0.3.3`
- swift-nio `2.65.0`
- swift-crypto `2.0.0`

如果 GitHub 网络抖动，重新跑一次 workflow 即可。

---

## 安全说明

- Agent 使用自签名 TLS 证书；App 不依赖公共 CA，而是固定配对时记录的 SHA-256 指纹。
- 配对阶段会临时接受自签名证书，但会用服务端返回的指纹做二次校验；不一致立即失败。
- SSH 主机密钥使用 TOFU；首次连接保存指纹，后续不匹配会拒绝。
- 密码、私钥、令牌、指纹只写 Keychain；UserDefaults 仅保存名称、地址、端口等元数据。
- 本项目不包含任何 Apple 签名证书或描述文件。

---

## 已知限制

- 未在真机上完成最终编译验证；首次云端构建可能需要根据 Xcode 报错做小幅修正。
- SSH 模式的 Windows 命令依赖 PowerShell 与 CIM，老版本 Windows 可能缺少 `Get-NetAdapterStatistics`。
- Linux 清理需要 root 或 sudo 密码；没有权限时命令会失败并在日志里显示。
- 文件上传目前一次性读入内存，超大文件建议先用 SSH/SFTP 工具传输。
- 无线 ADB 与 Android 发布签名不在本工程范围内。
